@export()
@description('Returns a name for azure resources.')
func resourceName(prefix string,  appName string, environment string) string => '${prefix}-${appName}-${environment}'

@export()
@description('Returns a unique name for azure resources.')
func uniqueResourceName(prefix string,  appName string, environment string) string => '${prefix}-${appName}-${environment}-${uniqueString(resourceGroup().id, subscription().id)}'
