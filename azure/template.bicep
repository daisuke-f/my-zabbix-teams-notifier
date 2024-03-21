param connections_teams_name string = 'connection_to_teams'
param connections_azuretables_name string = 'connection_to_azuretables'
param logic_app_name string = 'teams_poster_logic_app'
param storageAccount_name string = 'storage${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccount_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
  }

  resource tableServices 'tableServices@2023-01-01' = {
    name: 'default'

    resource table 'tables@2023-01-01' = {
      name: 'problems'
    }
  }
}

resource connections_azuretables 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_azuretables_name
  location: location
  properties: {
    displayName: 'connection_to_azure_table'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuretables')
    }
    parameterValues: {
      storageaccount: storageAccount_name
      sharedkey: storageAccount.listKeys(storageAccount.apiVersion).keys[0].value
    }
  }
}

resource connections_teams 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_teams_name
  location: location
  properties: {
    displayName: 'connection_to_teams'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
    }
  }
}

resource logic_app 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logic_app_name
  location: location
  tags: {
    name: 'Post in Teams channel'
  }
  properties: {
    state: 'Enabled'

    parameters: {
      '$connections': {
        value: {
          azuretables: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuretables')
            connectionId: connections_azuretables.id
            connectionName: 'azuretables'
          }
          teams: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
            connectionId: connections_teams.id
            connectionName: 'teams'
          }
        }
      }
    }

    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        groupId: {
          type: 'string'
          defaultValue: ''
        }
        channelId: {
          type: 'string'
          defaultValue: ''
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        POST_trigger: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                event_id: {
                  type: 'string'
                }
                subject: {
                  type: 'string'
                }
                message: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Check_message_with_event_id: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuretables\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/storageAccounts/@{encodeURIComponent(encodeURIComponent(\'AccountNameFromSettings\'))}/tables/@{encodeURIComponent(\'problems\')}/entities(PartitionKey=\'@{encodeURIComponent(\'problem\')}\',RowKey=\'@{encodeURIComponent(triggerBody()?[\'event_id\'])}\')'
          }
        }
        Switch: {
          type: 'Switch'
          expression: '@outputs(\'Check_message_with_event_id\').statusCode'
          runAfter: {
            Check_message_with_event_id: [
              'Succeeded'
              'Failed'
            ]
          }
          cases: {
            Not_found: {
              case: 404
              actions: {
                Post_new_message: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: {
                      recipient: {
                        groupId: '@parameters(\'groupId\')'
                        channelId: '@parameters(\'channelId\')'
                      }
                      messageBody: '<p>@{triggerBody()?[\'message\']}</p>'
                      subject: '@triggerBody()?[\'subject\']'
                    }
                    path: '/beta/teams/conversation/message/poster/@{encodeURIComponent(\'User\')}/location/@{encodeURIComponent(\'Channel\')}'
                  }
                }
                Save_message_id: {
                  runAfter: {
                    Post_new_message: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuretables\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '@concat(\'{"PartitionKey":"problem","RowKey":"\', triggerBody().event_id, \'","messageId":"\', outputs(\'Post_new_message\').body.id, \'"}\')'
                    path: '/v2/storageAccounts/@{encodeURIComponent(encodeURIComponent(\'AccountNameFromSettings\'))}/tables/@{encodeURIComponent(\'problems\')}/entities'
                  }
                }
              }
            }
            Found: {
              case: 200
              actions: {
                Reply_to_message: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: {
                      parentMessageId: '@{outputs(\'Check_message_with_event_id\').body.messageId}'
                      recipient: {
                        groupId: '@parameters(\'groupId\')'
                        channelId: '@parameters(\'channelId\')'
                      }
                      messageBody: '<p><b>@{triggerBody()?[\'subject\']}</b></p><p>@{triggerBody()?[\'message\']}</p>'
                    }
                    path: '/v1.0/teams/conversation/replyWithMessage/poster/@{encodeURIComponent(\'User\')}/location/@{encodeURIComponent(\'Channel\')}'
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Raise_error: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Failed'
                  runError: {
                    code: '500'
                  }
                }
              }
            }
          }
        }
      }
      outputs: {}
    }
  }
}
