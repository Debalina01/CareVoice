$loginBody = @{ Email = 'caregiver@carevoice.app'; Password = 'Password123!' } | ConvertTo-Json
$auth = Invoke-RestMethod -Uri 'http://localhost:5070/api/auth/login' -Method Post -Body $loginBody -ContentType 'application/json' -UseBasicParsing
$token = $auth.accessToken
$headers = @{ 'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' }

# Get members to find Papa
$members = Invoke-RestMethod -Uri 'http://localhost:5070/api/family-members' -Method Get -Headers $headers -UseBasicParsing
$papa = $members | Where-Object { $_.relation -eq 'Parent' -or $_.fullName -like '*Papa*' } | Select-Object -First 1
if (-not $papa) { $papa = $members[0] }
Write-Host "Target Member: $($papa.fullName) ($($papa.id))"

# Turn 1: User says "set the reminder for papa"
Write-Host "`n--- Turn 1: 'set the reminder for papa' ---"
$req1 = @{
    Message = 'set the reminder for papa'
    Language = 'en'
} | ConvertTo-Json
$res1 = Invoke-RestMethod -Uri 'http://localhost:5070/api/ai/serbom/process' -Method Post -Body $req1 -Headers $headers -UseBasicParsing
Write-Host "AI Response 1: $($res1.replyMessage)"
Write-Host "Status: $($res1.status), Missing: $($res1.missingFields -join ', ')"
Write-Host "Accumulated Member: $($res1.extractedSchedule.targetMemberName)"

# Turn 2: User says "paracetamol"
Write-Host "`n--- Turn 2: 'paracetamol' ---"
$req2 = @{
    Message = 'paracetamol'
    Language = 'en'
    AccumulatedSchedule = $res1.extractedSchedule
} | ConvertTo-Json -Depth 5
$res2 = Invoke-RestMethod -Uri 'http://localhost:5070/api/ai/serbom/process' -Method Post -Body $req2 -Headers $headers -UseBasicParsing
Write-Host "AI Response 2: $($res2.replyMessage)"
Write-Host "Status: $($res2.status), Missing: $($res2.missingFields -join ', ')"
Write-Host "Accumulated Medicine: $($res2.extractedSchedule.medicineName), Member: $($res2.extractedSchedule.targetMemberName)"

# Turn 3: User says "500mg"
Write-Host "`n--- Turn 3: '500mg' ---"
$req3 = @{
    Message = '500mg'
    Language = 'en'
    AccumulatedSchedule = $res2.extractedSchedule
} | ConvertTo-Json -Depth 5
$res3 = Invoke-RestMethod -Uri 'http://localhost:5070/api/ai/serbom/process' -Method Post -Body $req3 -Headers $headers -UseBasicParsing
Write-Host "AI Response 3: $($res3.replyMessage)"
Write-Host "Status: $($res3.status), Missing: $($res3.missingFields -join ', ')"
Write-Host "Accumulated Dosage: $($res3.extractedSchedule.dosage)"

# Turn 4: User says "at 8am after breakfast"
Write-Host "`n--- Turn 4: 'at 8am after breakfast' ---"
$req4 = @{
    Message = 'at 8am after breakfast'
    Language = 'en'
    AccumulatedSchedule = $res3.extractedSchedule
} | ConvertTo-Json -Depth 5
$res4 = Invoke-RestMethod -Uri 'http://localhost:5070/api/ai/serbom/process' -Method Post -Body $req4 -Headers $headers -UseBasicParsing
Write-Host "AI Response 4: $($res4.replyMessage)"
Write-Host "Status: $($res4.status)"
Write-Host "FINAL SCHEDULE READY:"
Write-Host " - Medicine: $($res4.extractedSchedule.medicineName)"
Write-Host " - Dosage: $($res4.extractedSchedule.dosage)"
Write-Host " - Member: $($res4.extractedSchedule.targetMemberName)"
Write-Host " - Times: $($res4.extractedSchedule.timesOfDay -join ', ')"
Write-Host " - Food: $($res4.extractedSchedule.foodRelation)"
