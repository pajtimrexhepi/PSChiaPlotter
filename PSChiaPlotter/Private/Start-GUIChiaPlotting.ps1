function Start-GUIChiaPlotting {
    [CmdletBinding()]
    param(
        #[string]$SecondTempDirecoryPath,
        #$FarmerPublicKey,
        #$PoolPublicKey,

        $ChiaRun,
        $ChiaQueue,
        $ChiaJob
    )

    #not really needed, but just wanted to make each parameter its own variable
    $PlottingParameters = $ChiaRun.PlottingParameters
    $KSize = $PlottingParameters.KSize
    $Buffer = $PlottingParameters.RAM
    $Threads = $PlottingParameters.Threads
    $DisableBitfield = $PlottingParameters.DisableBitField
    $ExcludeFinalDirectory = $PlottingParameters.ExcludeFinalDirectory
    $TempDirectoryPath = $PlottingParameters.TempVolume.DirectoryPath
    $FinalDirectoryPath = $PlottingParameters.FinalVolume.DirectoryPath
    $LogDirectoryPath = $PlottingParameters.LogDirectory
    #$SecondTempDirecoryPath = $PlottingParameters.TempVolume.DirectoryPath
    $PoolPublicKey = $PlottingParameters.PoolPublicKey
    $FarmerPublicKey = $PlottingParameters.FarmerPublicKey

    $E = if ($DisableBitfield){"-e"}
    $X = if ($ExcludeFinalDirectory){"-x"}

    #remove any trailing '\' since chia.exe hates them
    $TempDirectoryPath = $TempDirectoryPath.TrimEnd('\')
    $FinalDirectoryPath = $FinalDirectoryPath.TrimEnd('\')

    #path to chia.exe
    $ChiaPath = (Get-Item -Path "$ENV:LOCALAPPDATA\chia-blockchain\app-*\resources\app.asar.unpacked\daemon\chia.exe").FullName
    $ChiaArguments = "plots create -k $KSize -b $Buffer -r $Threads -t `"$TempDirectoryPath`" -d `"$FinalDirectoryPath`" $E $X"

    if (-not[string]::IsNullOrWhiteSpace($PoolPublicKey)){
        $ChiaArguments += " -p $PoolPublicKey"
    }
    if (-not[string]::IsNullOrWhiteSpace($FarmerPublicKey)){
        $ChiaArguments += " -f $FarmerPublicKey"
    }

    if ($ChiaPath){
        Write-Information "Chia path exists, starting the plotting process"
        try{
            $LogPath = Join-Path $LogDirectoryPath ((Get-Date -Format yyyy_MM_dd_hh-mm-ss-tt_) + "plotlog-" + $ChiaQueue.QueueNumber + "-" + $ChiaRun.RunNumber + ".log")
            $ChiaRun.LogPath = $LogPath
            $PlottingParam = @{
                FilePath = $ChiaPath
                ArgumentList = $ChiaArguments
                RedirectStandardOutput = $LogPath
            }
            $chiaProcess = Start-Process @PlottingParam -PassThru -WindowStyle Hidden


            #this is 100% require for th exit code to be seen by powershell when redirectingstandardoutput
            $handle = $chiaProcess.Handle

            $ChiaRun.ChiaProcess = $ChiaProcess
            $ChiaRun.ProcessId = $ChiaProcess.Id
            $ChiaJob.RunsInProgress.Add($ChiaRun)

            $ChiaRun.PlottingParameters.TempVolume.CurrentChiaRuns.Add($ChiaRun)
            $TempMasterVolume = $DataHash.MainViewModel.AllVolumes | where DriveLetter -eq $ChiaRun.PlottingParameters.TempVolume.DriveLetter
            $TempMasterVolume.CurrentChiaRuns.Add($ChiaRun)
            $FinalMasterVolume = $DataHash.MainViewModel.AllVolumes | where DriveLetter -eq $ChiaRun.PlottingParameters.FinalVolume.DriveLetter
            $FinalMasterVolume.PendingFinalRuns.Add($ChiaRun)

            $ChiaQueue.CurrentRun = $ChiaRun
            $DataHash.MainViewModel.CurrentRuns.Add($ChiaRun)
            $DataHash.MainViewModel.AllRuns.Add($ChiaRun)

            #Have noticed that giving the process a second to start before checking the logs works better
            Start-Sleep 1
        
            while (!$chiaProcess.HasExited){
                try{
                    $progress = Get-ChiaPlotProgress -LogPath $LogPath -ErrorAction Stop
                    $plotid = $progress.PlotId
                    $ChiaRun.Progress = $progress.progress
                    $ChiaQueue.CurrentTime = [DateTime]::Now
                    $ChiaRun.CurrentTime = [DateTime]::Now
                    $ChiaRun.Phase = $progress.Phase
                    if ($progress.EST_TimeReamining.TotalSeconds -le 0){
                        $ChiaRun.EstTimeRemaining = New-TimeSpan -Seconds 0
                    }
                    else{
                        $ChiaRun.EstTimeRemaining = $progress.EST_TimeReamining
                    }
                    $ChiaRun.EstTimeRemaining = $progress.EST_TimeReamining
                    $ChiaRun.TempSize = Get-ChiaTempSize -DirectoryPath $TempDirectoryPath -PlotId $plotid
                    Start-Sleep (5 + $ChiaQueue.QueueNumber)
                }
                catch{
                    Start-Sleep 30
                }
            } #while

            $ChiaJob.RunsInProgress.Remove($ChiaRun)
            $ChiaJob.CompletedRunCount++
            $FinalMasterVolume.PendingFinalRuns.Remove($ChiaRun)
            $TempMasterVolume.CurrentChiaRuns.Remove($ChiaRun)
            $ChiaRun.ExitCode = $ChiaRun.ChiaPRocess.ExitCode
            #if this is null then an error will occur if we try to set this property
            if ($ChiaRun.ExitTime){
                $ChiaRun.ExitTime = $ChiaProcess.ExitTime
            }

            if ($ChiaRun.ChiaPRocess.ExitCode -ne 0){
                $ChiaRun.Status = "Failed"
                $ChiaQueue.FailedPlotCount++
                $ChiaJob.FailedPlotCount++
                $DataHash.MainViewModel.FailedRuns.Add($ChiaRun)
                Get-ChildItem -Path $TempDirectoryPath -Filter "*$plotid*.tmp" | foreach {
                    try{
                        Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    }
                    catch{
                        Show-Messagebox -Text $_.Exception.Message | Out-Null
                    }
                }
            }
            else{
                $ChiaRun.Status = "Completed"
                $ChiaJob.CompletedPlotCount++
                $ChiaQueue.CompletedPlotCount++
                $DataHash.MainViewModel.CompletedRuns.Add($ChiaRun)
                Update-ChiaGUISummary -Success
            }
            $DataHash.MainViewModel.CurrentRuns.Remove($ChiaRun)
            $ChiaRun.PlottingParameters.TempVolume.CurrentChiaRuns.Remove($ChiaRun)
        }
        catch{
            if (-not$DataHash.MainViewModel.FailedRuns.Contains($ChiaRun)){
                $DataHash.MainViewModel.FailedRuns.Add($ChiaRun)
            }
            if ($DataHash.MainViewModel.CurrentRuns.Contains($ChiaRun)){
                $DataHash.MainViewModel.CurrentRuns.Remove($ChiaRun)
            }
            if ($ChiaJob.RunsInProgress.Contains($ChiaRun)){
                $ChiaJob.RunsInProgress.Remove($ChiaRun)
            }
            if ($FinalMasterVolume){
                if ($FinalMasterVolume.PendingFinalRuns.Contains($ChiaRun)){
                    $FinalMasterVolume.PendingFinalRuns.Remove($ChiaRun)
                }
            }
            $PSCmdlet.WriteError($_)
        }
    } #if chia path exits
    else{
        $Message = "chia.exe was not found"
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new($Message,"$ENV:LOCALAPPDATA\chia-blockchain\app-*\resources\app.asar.unpacked\daemon\chia.exe"),
                'ChiaPathInvalid',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                "$ENV:LOCALAPPDATA\chia-blockchain\app-*\resources\app.asar.unpacked\daemon\chia.exe"
            )
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        $PSCmdlet.ThrowTerminatingError("Invalid Log Path Directory: $LogDirectoryPath")
    }
}