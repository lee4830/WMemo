$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$box = New-Object System.Windows.Forms.TextBox
$form.Controls.Add($box)
Write-Host "WinForms compatibility OK"
