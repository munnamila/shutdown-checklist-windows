[CmdletBinding()]
param([switch]$ValidateOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $appDir 'checklist.json'

function Show-FatalError {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'シャットダウン前チェックリスト',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "設定ファイルが見つかりません：$configPath"
    }
    $config = Get-Content -Raw -LiteralPath $configPath -Encoding UTF8 | ConvertFrom-Json
    $items = @($config.items | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { throw '設定ファイルにはチェック項目が1つ以上必要です。' }
    $delaySeconds = [int]$config.delay_seconds
    if ($delaySeconds -lt 10 -or $delaySeconds -gt 3600) {
        throw 'delay_seconds は10～3600の整数にしてください。'
    }
    $windowTitle = if ($null -ne $config.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$config.title)) {
        [string]$config.title
    } else {
        'シャットダウン前チェックリスト'
    }
} catch {
    Show-FatalError "checklist.json を読み込めませんでした。`r`n`r`n$($_.Exception.Message)"
}

if ($ValidateOnly) {
    Write-Output "Validation passed: $($items.Count) items, $delaySeconds second delay."
    exit 0
}

$script:shutdownScheduled = $false
$script:countdownTimer = $null
$script:remaining = 0

$form = New-Object System.Windows.Forms.Form
$form.Text = $windowTitle
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(560, 520)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 248, 250)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'シャットダウン前にご確認ください'
$titleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 35, 45)
$titleLabel.Location = New-Object System.Drawing.Point(28, 24)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = 'すべての項目をチェックするとシャットダウンできます。'
$hintLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 96, 108)
$hintLabel.Location = New-Object System.Drawing.Point(31, 65)
$hintLabel.AutoSize = $true
$form.Controls.Add($hintLabel)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(28, 100)
$panel.Size = New-Object System.Drawing.Size(504, 330)
$panel.AutoScroll = $true
$panel.BackColor = [System.Drawing.Color]::White
$panel.BorderStyle = 'FixedSingle'
$form.Controls.Add($panel)

$checkboxes = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]
$y = 18
foreach ($item in $items) {
    $box = New-Object System.Windows.Forms.CheckBox
    $box.Text = $item
    $box.Location = New-Object System.Drawing.Point(18, $y)
    $box.Size = New-Object System.Drawing.Size(450, 42)
    $box.AutoEllipsis = $true
    $box.UseVisualStyleBackColor = $true
    $checkboxes.Add($box)
    $panel.Controls.Add($box)
    $y += 50
}

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'キャンセル'
$cancelButton.Location = New-Object System.Drawing.Point(326, 456)
$cancelButton.Size = New-Object System.Drawing.Size(96, 40)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

$shutdownButton = New-Object System.Windows.Forms.Button
$shutdownButton.Text = 'シャットダウン'
$shutdownButton.Location = New-Object System.Drawing.Point(432, 456)
$shutdownButton.Size = New-Object System.Drawing.Size(100, 40)
$shutdownButton.Enabled = $false
$shutdownButton.BackColor = [System.Drawing.Color]::FromArgb(205, 63, 68)
$shutdownButton.ForeColor = [System.Drawing.Color]::White
$shutdownButton.FlatStyle = 'Flat'
$shutdownButton.FlatAppearance.BorderSize = 0
$form.Controls.Add($shutdownButton)

$updateButtonState = {
    $allChecked = $true
    foreach ($box in $checkboxes) {
        if (-not $box.Checked) { $allChecked = $false; break }
    }
    $shutdownButton.Enabled = $allChecked
}
foreach ($box in $checkboxes) { $box.Add_CheckedChanged($updateButtonState) }

$cancelButton.Add_Click({
    if (-not $script:shutdownScheduled) {
        $form.Close()
        return
    }
    try {
        $abort = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/a' -PassThru -Wait -WindowStyle Hidden
        if ($abort.ExitCode -ne 0) { throw "shutdown.exe の終了コード：$($abort.ExitCode)" }
        $script:shutdownScheduled = $false
        $script:countdownTimer.Stop()
        [System.Windows.Forms.MessageBox]::Show('シャットダウンを取り消しました。', 'シャットダウン前チェックリスト', 'OK', 'Information') | Out-Null
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("シャットダウンを取り消せませんでした。`r`n`r`n$($_.Exception.Message)", '取り消しエラー', 'OK', 'Error') | Out-Null
    }
})

$form.Add_FormClosing({
    if ($script:shutdownScheduled) {
        $_.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show('シャットダウンのカウントダウン中です。先に「シャットダウンを取り消す」をクリックしてください。', 'シャットダウン前チェックリスト', 'OK', 'Information') | Out-Null
    }
})

$shutdownButton.Add_Click({
    & $updateButtonState
    if (-not $shutdownButton.Enabled) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "すべての項目を確認しました。$delaySeconds 秒後にシャットダウンしますか？",
        'シャットダウンの確認',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList @('/s', '/t', "$delaySeconds", '/c', 'シャットダウン前の確認が完了しました。') -PassThru -Wait -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "shutdown.exe の終了コード：$($process.ExitCode)" }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("シャットダウンを開始できませんでした。`r`n`r`n$($_.Exception.Message)", 'シャットダウンエラー', 'OK', 'Error') | Out-Null
        return
    }
    $script:remaining = $delaySeconds
    $script:shutdownScheduled = $true
    foreach ($box in $checkboxes) { $box.Enabled = $false }
    $shutdownButton.Visible = $false
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::None
    $cancelButton.Text = 'シャットダウンを取り消す'
    $cancelButton.Location = New-Object System.Drawing.Point(302, 456)
    $cancelButton.Size = New-Object System.Drawing.Size(230, 40)
    $titleLabel.Text = "$script:remaining 秒後にシャットダウンします"
    $hintLabel.Text = '使用を続ける場合は「シャットダウンを取り消す」をクリックしてください。'
    $script:countdownTimer = New-Object System.Windows.Forms.Timer
    $script:countdownTimer.Interval = 1000
    $script:countdownTimer.Add_Tick({
        $script:remaining--
        if ($script:remaining -le 0) {
            $script:countdownTimer.Stop()
            $script:shutdownScheduled = $false
            $form.Close()
        } else {
            $titleLabel.Text = "$script:remaining 秒後にシャットダウンします"
        }
    })
    $script:countdownTimer.Start()
})

[void]$form.ShowDialog()

