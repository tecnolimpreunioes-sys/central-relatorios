# Registra o worker no Agendador de Tarefas da TECNOLIMP12: inicia com o Windows,
# sem limite de tempo de execução e com reinício automático. Rodar como administrador:
#   powershell -ExecutionPolicy Bypass -File .\instalar_tarefa.ps1
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$nome  = "Tecnolimp - Quadro de Vagas (worker)"
$acao  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$pasta\iniciar_worker.bat`"" -WorkingDirectory $pasta
$gatilho = New-ScheduledTaskTrigger -AtStartup
$config  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 `
           -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
$cred = Get-Credential -Message "Usuário do Windows que roda o worker (o mesmo do PYEXE)" -UserName "$env:USERDOMAIN\$env:USERNAME"
Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Settings $config `
  -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $nome
Write-Host "Tarefa '$nome' registrada e iniciada. Log: $pasta\logs\worker_quadro_vagas.log"
