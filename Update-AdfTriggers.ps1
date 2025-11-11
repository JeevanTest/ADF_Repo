param (
    [string]$resourceGroup,
    [string]$dataFactoryName,
    [string]$triggerConfigPath
)

# Suppress confirmation prompts globally
# $ConfirmPreference = 'None'

Write-Host "Loading trigger config from $triggerConfigPath"
$triggerConfig = Get-Content $triggerConfigPath | ConvertFrom-Json

foreach ($triggerName in $triggerConfig.PSObject.Properties.Name) {
    $config = $triggerConfig.$triggerName
    Write-Host "Processing trigger: $triggerName"

    try {
        # Validate trigger exists
        $existingTrigger = Get-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroup -DataFactoryName $dataFactoryName -Name $triggerName -ErrorAction SilentlyContinue
        if ($null -eq $existingTrigger) {
            Write-Host "Trigger '$triggerName' does not exist. Skipping..."
            continue
        }

        # Stop the trigger before update
        Write-Host "Stopping trigger '$triggerName' before update..."
        Stop-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroup -DataFactoryName $dataFactoryName -Name $triggerName -Force

        # Build trigger definition object
        $triggerDefinition = @{
            name = $triggerName
            properties = @{
                type = "ScheduleTrigger"
                typeProperties = @{
                    recurrence = @{
                        frequency = $config.recurrence.frequency
                        interval = $config.recurrence.interval
                        startTime = $config.recurrence.startTime
                        timeZone = $config.recurrence.timeZone
                    }
                }
                pipelines = @()
            }
        }

        foreach ($pipeline in $config.pipelines) {
            $triggerDefinition.properties.pipelines += @{
                pipelineReference = @{
                    type = "PipelineReference"
                    referenceName = $pipeline.referenceName
                }
                parameters = $pipeline.parameters
            }
        }

        # Write the trigger definition to temporary JSON file
        $tempFile = [System.IO.Path]::GetTempFileName()
        $triggerDefinition | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempFile -Encoding utf8

        # Update the trigger using the definition file
        Set-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroup -DataFactoryName $dataFactoryName -Name $triggerName -DefinitionFile $tempFile -Force
        Write-Host "Trigger '$triggerName' updated successfully."

        # Start or stop the trigger based on config
        if ($config.runtimeState -eq "Started") {
            Start-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroup -DataFactoryName $dataFactoryName -Name $triggerName -Force
            Write-Host "Trigger '$triggerName' started."
        } else {
            Write-Host "Trigger '$triggerName' left in stopped state."
        }

        $updatedTrigger = Get-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroup -DataFactoryName $dataFactoryName -Name $triggerName
        Write-Host "Validated trigger '$triggerName' is in state: $($updatedTrigger.RuntimeState)"

        # Clean up temp file
        Remove-Item $tempFile -Force
    }
    catch {
        Write-Host "Error processing trigger ${triggerName}: $_"
    }
}
