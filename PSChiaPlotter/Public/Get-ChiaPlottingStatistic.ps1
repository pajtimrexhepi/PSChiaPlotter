function Get-ChiaPlottingStatistic {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [string[]]$Path = (Get-ChildItem -Path $env:USERPROFILE\.chia\mainnet\plotter\ | sort CreationTime -Descending).FullName
    )

    Process{
        foreach ($log in $path){
            if (Test-Path $log){
                $Content = Get-Content -Path $log | Select-String "ID: ","Time for phase","Total time","Plot size","Buffer size","threads of stripe","Copy time","Copied final file from","Starting plotting progress into temporary dirs" | foreach {$_.ToString()}
                foreach ($line in $Content){
                    switch -Wildcard ($line){
                        "ID: *" {$PlotID = $line.Split(' ') | select -Skip 1 -First 1}
                        "Plot size*" {$PlotSize = $line.split(' ') | select -Skip 3} #using select for these since indexing will error if empty
                        "Buffer Size*" {$BufferSize = ($line.Split(' ') | select -Skip 3).split("M") | select -First 1}
                        "*threads*" {$ThreadCount = $line.split(' ') | select -First 1 -Skip 1}
                        "*phase 1*" {$Phase_1 = $line.Split(' ') | select -First 1 -Skip 5}
                        "*phase 2*" {$Phase_2 = $line.Split(' ') | select -First 1 -Skip 5}
                        "*phase 3*" {$Phase_3 = $line.Split(' ') | select -First 1 -Skip 5}
                        "*phase 4*" {$phase_4 = $line.Split(' ') | select -First 1 -Skip 5}
                        "Total time*" {$TotalTime = $line.Split(' ') | select -First 1 -Skip 3}
                        "Copy time*" {$CopyTime = $line.Split(' ') | select -First 1 -Skip 3}
                        "Starting plotting progress into temporary dirs*" {$TempDrive = ($line.Split(' ') | select -First 1 -Skip 6).Split('\') | select -First 1 }
                        "Copied final file from*" {$FinalDrive = ($line.Split(' ') | select -First 1 -Skip 6).Split('\').Replace('"', '') | select -First 1}
                        default {Write-Information "Could not match line: $line"}
                    }
                }
                [PSCustomObject]@{
                    PSTypeName = "PSChiaPlotter.ChiaPlottingStatistic"
                    PlotId = $PlotID
                    KSize = $PlotSize
                    "RAM(MiB)" = $BufferSize
                    Threads = $ThreadCount
                    "Phase_1_sec" = [int]$Phase_1
                    "Phase_2_sec" = [int]$Phase_2
                    "Phase_3_sec" = [int]$Phase_3
                    "Phase_4_sec" = [int]$phase_4
                    "TotalTime_sec" = [int]$TotalTime
                    "CopyTime_sec" = [int]$CopyTime
                    "PlotAndCopyTime_sec" = ([int]$CopyTime + [int]$TotalTime)
                    "Time_Started" = (Get-Item -Path $log).CreationTime 
                    "Temp_drive" = $TempDrive
                    "Final_drive" = $FinalDrive
                }
                Clear-Variable -Name "PlotID","PlotSize","BufferSize","ThreadCount","Phase_1","Phase_2","Phase_3","Phase_4","TotalTime","CopyTime","FinalDrive","TempDrive" -ErrorAction SilentlyContinue
            }
        }
    }
}