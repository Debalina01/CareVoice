$baseUrl = "http://localhost:5070"

Write-Host "=== CAREVOICE PHASE 3 INTEGRATION TEST ===" -ForegroundColor Cyan

# 1. Register User
$email = "caregiver_p3_" + (Get-Random) + "@carevoice.app"
$body = @{
    Email = $email
    Password = "Password123!"
    FullName = "Phase 3 Caregiver"
    PhoneNumber = "+1234567890"
} | ConvertTo-Json

$reg = Invoke-RestMethod -Uri "$baseUrl/api/auth/register" -Method Post -Body $body -ContentType "application/json"
$token = $reg.accessToken
$headers = @{ Authorization = "Bearer $token" }
$selfMemberId = $reg.user.defaultFamilyMemberId
Write-Host "[1/7] User registered with Self member: $selfMemberId" -ForegroundColor Green

# 2. Create Medicine
$medBody = @{
    OwnerMemberId = $selfMemberId
    Name = "Atorvastatin 20mg"
    Dosage = "1 Tablet"
    Instructions = "Take at night"
    FoodRelation = "NoRelation"
    StartDate = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json

$med = Invoke-RestMethod -Uri "$baseUrl/api/medicines" -Method Post -Headers $headers -Body $medBody -ContentType "application/json"
$medId = $med.id
Write-Host "[2/7] Medicine created: $($med.name) (ID: $medId)" -ForegroundColor Green

# 3. Create Schedule
$schedBody = @{
    MedicineId = $medId
    TargetMemberId = $selfMemberId
    TimeOfDay = "20:00"
    DaysOfWeekMask = 127
} | ConvertTo-Json

$sched = Invoke-RestMethod -Uri "$baseUrl/api/schedules" -Method Post -Headers $headers -Body $schedBody -ContentType "application/json"
$schedId = $sched.id
Write-Host "[3/7] Schedule created for 20:00 (ID: $schedId)" -ForegroundColor Green

# 4. Test 48-Hour Sync Window
$syncDoses = Invoke-RestMethod -Uri "$baseUrl/api/schedules/sync" -Method Get -Headers $headers
if ($syncDoses.Count -ge 1) {
    Write-Host "[4/7] 48-Hour Sync returned $($syncDoses.Count) upcoming dose instances" -ForegroundColor Green
} else {
    Write-Host "[4/7] FAILED: No doses returned in sync window." -ForegroundColor Red; exit 1
}

# 5. Sync Offline Action (Taken)
$clientLogId = [guid]::NewGuid().ToString()
$singleAction = @{
    ClientLogId = $clientLogId
    ScheduleId = $schedId
    TargetMemberId = $selfMemberId
    ScheduledTime = (Get-Date).ToUniversalTime().ToString("o")
    ActionTime = (Get-Date).ToUniversalTime().ToString("o")
    Status = "Taken"
} | ConvertTo-Json
$logAction = "[$singleAction]"

$syncRes = Invoke-RestMethod -Uri "$baseUrl/api/logs/sync" -Method Post -Headers $headers -Body $logAction -ContentType "application/json"
if ($syncRes[0].success -eq $true) {
    Write-Host "[5/7] Synced dose action 'Taken' successfully (ClientLogId: $clientLogId)" -ForegroundColor Green
} else {
    Write-Host "[5/7] FAILED: Dose sync failed: $($syncRes[0].message)" -ForegroundColor Red; exit 1
}

# 6. Test Idempotency (Re-syncing same ClientLogId)
$syncRes2 = Invoke-RestMethod -Uri "$baseUrl/api/logs/sync" -Method Post -Headers $headers -Body $logAction -ContentType "application/json"
if ($syncRes2[0].success -eq $true -and $syncRes2[0].message -like "*duplicate*") {
    Write-Host "[6/7] Idempotency verified: duplicate action correctly deduplicated" -ForegroundColor Green
} else {
    Write-Host "[6/7] FAILED: Idempotency check failed: $($syncRes2[0].message)" -ForegroundColor Red; exit 1
}

# 7. Check Adherence History
$history = Invoke-RestMethod -Uri "$baseUrl/api/logs/history" -Method Get -Headers $headers
if ($history.Count -ge 1 -and $history[0].clientLogId -eq $clientLogId) {
    Write-Host "[7/7] Adherence history query verified (Status: $($history[0].status))" -ForegroundColor Green
} else {
    Write-Host "[7/7] FAILED: History query did not match expected log." -ForegroundColor Red; exit 1
}

Write-Host "=== ALL 7 PHASE 3 BACKEND CHECKS PASSED SUCCESSFULLY ===" -ForegroundColor Green
