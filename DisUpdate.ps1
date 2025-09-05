# ================================
# Disable Windows Update - Win10
# PowerShell 5.x - Run as Admin
# ================================

# 0) Yêu cầu quyền Admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Error "Hãy mở PowerShell bằng Run as Administrator rồi chạy lại."
  exit 1
}

# 1) Tạo điểm khôi phục (nếu bật System Protection)
try {
  Checkpoint-Computer -Description "DisableWindowsUpdate" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
} catch {}

# 2) Áp chính sách chặn tự động update
$WUKey     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$AUKey     = "$WUKey\AU"
New-Item -Path $WUKey -Force | Out-Null
New-Item -Path $AUKey -Force | Out-Null

# Tắt auto update
Set-ItemProperty -Path $AUKey -Name "NoAutoUpdate" -Type DWord -Value 1
# Không kết nối tới hệ thống Windows Update Internet Locations
Set-ItemProperty -Path $WUKey -Name "DoNotConnectToWindowsUpdateInternetLocations" -Type DWord -Value 1
# Không kéo driver qua Windows Update (giảm noise)
Set-ItemProperty -Path $WUKey -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1
# Chặn nâng cấp OS lớn (Feature Upgrade)
Set-ItemProperty -Path $WUKey -Name "DisableOSUpgrade" -Type DWord -Value 1

# 3) Vô hiệu hoá các dịch vụ chính của Windows Update
$services = @(
  "wuauserv",       # Windows Update
  "WaaSMedicSvc",   # Windows Update Medic Service
  "UsoSvc",         # Update Orchestrator Service
  "DoSvc",          # Delivery Optimization
  "BITS"            # Background Intelligent Transfer Service (WU hay dùng)
)

foreach ($s in $services) {
  try { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } catch {}
  try { Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
  # Ép mức khởi động = Disabled trực tiếp trong registry (Start=4)
  $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
  if (Test-Path $svcKey) {
    try { Set-ItemProperty -Path $svcKey -Name "Start" -Type DWord -Value 4 -ErrorAction SilentlyContinue } catch {}
  }
}

# 4) Vô hiệu hoá các Scheduled Tasks liên quan tới Update
$tasks = @(
  "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
  "\Microsoft\Windows\WindowsUpdate\Scheduled Start With Network",
  "\Microsoft\Windows\WindowsUpdate\Automatic App Update",
  "\Microsoft\Windows\WindowsUpdate\SIH",
  "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
  "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker",
  "\Microsoft\Windows\UpdateOrchestrator\Reboot",
  "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC",
  "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery",
  "\Microsoft\Windows\UpdateOrchestrator\Maintenance Install"
)

foreach ($t in $tasks) {
  try { schtasks /Change /TN $t /Disable 2>$null | Out-Null } catch {}
}

# 5) Áp GPO ngay (nếu có)
try { gpupdate /force | Out-Null } catch {}

Write-Host "`n✅ Đã vô hiệu hoá Windows Update ở mức hệ thống. Khuyến nghị khởi động lại máy."
