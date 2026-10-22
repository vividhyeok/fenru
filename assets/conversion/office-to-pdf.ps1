param([Parameter(Mandatory=$true)][string]$Source,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$app = $null
$document = $null
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FenruConversionProcess {
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint process);
}
'@
function Save-ConverterProcess([long]$handle) {
    [uint32]$converterProcess = 0
    [void][FenruConversionProcess]::GetWindowThreadProcessId([IntPtr]$handle, [ref]$converterProcess)
    if ($converterProcess -gt 0) { [IO.File]::WriteAllText($Destination + '.process', $converterProcess.ToString()) }
}
try {
    $extension = [IO.Path]::GetExtension($Source).ToLowerInvariant()
    if ($extension -in @('.doc', '.docx', '.rtf')) {
        if (Get-Process WINWORD -ErrorAction SilentlyContinue) { throw 'Close Word before conversion or use LibreOffice.' }
        $app = New-Object -ComObject Word.Application
        $app.Visible = $false
        Save-ConverterProcess $app.Hwnd
        $app.DisplayAlerts = 0
        $app.AutomationSecurity = 3
        $app.Options.UpdateLinksAtOpen = $false
        $document = $app.Documents.Open($Source, $false, $true, $false, '', '', $false, '', '', 0, '', $false, $false, 0, $true)
        $document.ExportAsFixedFormat($Destination, 17, $false)
    } elseif ($extension -in @('.ppt', '.pptx')) {
        if (Get-Process POWERPNT -ErrorAction SilentlyContinue) { throw 'Close PowerPoint before conversion or use LibreOffice.' }
        $app = New-Object -ComObject PowerPoint.Application
        Save-ConverterProcess $app.HWND
        $app.AutomationSecurity = 3
        $app.DisplayAlerts = 1
        $document = $app.Presentations.Open($Source, -1, 0, 0)
        $document.SaveAs($Destination, 32)
    } elseif ($extension -in @('.hwp', '.hwpx')) {
        if (Get-Process Hwp -ErrorAction SilentlyContinue) { throw 'Close Hancom Hangul before conversion.' }
        $app = New-Object -ComObject HWPFrame.HwpObject
        $app.XHwpWindows.Item(0).Visible = $false
        Save-ConverterProcess $app.XHwpWindows.Item(0).WindowHandle
        # Respect Hancom's file access consent; no security module is installed/bypassed.
        if (!$app.Open($Source, '', 'versionwarning:false;forceopen:true')) { throw 'Cannot open Hangul document.' }
        if (!$app.SaveAs($Destination, 'PDF', '')) { throw 'Cannot export Hangul PDF.' }
    } else { throw 'Unsupported format.' }
    if (!(Test-Path -LiteralPath $Destination)) { throw 'PDF output missing.' }
    Write-Output 'PDF_OK'
} catch {
    Write-Output 'PDF_FAILED'
    exit 1
} finally {
    if ($document) {
        try { if ($extension -in @('.doc', '.docx', '.rtf')) { $document.Close(0) } else { $document.Close() } } catch {}
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($document)
    }
    if ($app) {
        try { $app.Quit() } catch {}
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($app)
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
