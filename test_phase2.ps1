$baseUrl = "http://localhost:5070"

Write-Host "=== CAREVOICE PHASE 2 INTEGRATION TEST ===" -ForegroundColor Cyan

# 1. Register Caregiver
$caregiverEmail = "caregiver_p2_" + (Get-Random) + "@carevoice.app"
$caregiverBody = @{
    Email = $caregiverEmail
    Password = "Password123!"
    FullName = "Phase 2 Caregiver"
    PhoneNumber = "+1987654321"
} | ConvertTo-Json

$cgReg = Invoke-RestMethod -Uri "$baseUrl/api/auth/register" -Method Post -Body $caregiverBody -ContentType "application/json"
$cgToken = $cgReg.accessToken
$cgHeaders = @{ Authorization = "Bearer $cgToken" }
Write-Host "[1/10] Caregiver registered: $caregiverEmail" -ForegroundColor Green

# 2. Get initial family members (Self)
$cgMembers = Invoke-RestMethod -Uri "$baseUrl/api/family-members" -Method Get -Headers $cgHeaders
if ($cgMembers.Count -ge 1 -and $cgMembers[0].isSelf -eq $true) {
    Write-Host "[2/10] Default 'Self' member verified: $($cgMembers[0].fullName)" -ForegroundColor Green
} else {
    Write-Host "[2/10] FAILED: Self member not found." -ForegroundColor Red; exit 1
}

# 3. Create a family member
$newMemberBody = @{
    FullName = "Grandma Mary"
    Relation = "Grandmother"
    PreferredLanguage = "en"
    VoicePreference = "en-US-Standard-B"
} | ConvertTo-Json

$createdMember = Invoke-RestMethod -Uri "$baseUrl/api/family-members" -Method Post -Headers $cgHeaders -Body $newMemberBody -ContentType "application/json"
Write-Host "[3/10] Created family member: $($createdMember.fullName) (ID: $($createdMember.id))" -ForegroundColor Green

# 4. Update family member
$updateBody = @{
    FullName = "Grandma Mary Smith"
    Relation = "Grandmother"
    PreferredLanguage = "es"
    VoicePreference = "es-ES-Standard-A"
} | ConvertTo-Json

$updatedMember = Invoke-RestMethod -Uri "$baseUrl/api/family-members/$($createdMember.id)" -Method Put -Headers $cgHeaders -Body $updateBody -ContentType "application/json"
if ($updatedMember.fullName -eq "Grandma Mary Smith" -and $updatedMember.preferredLanguage -eq "es") {
    Write-Host "[4/10] Updated family member details verified" -ForegroundColor Green
} else {
    Write-Host "[4/10] FAILED: Update did not apply." -ForegroundColor Red; exit 1
}

# 5. Prevent deleting 'Self'
try {
    Invoke-RestMethod -Uri "$baseUrl/api/family-members/$($cgMembers[0].id)" -Method Delete -Headers $cgHeaders
    Write-Host "[5/10] FAILED: Allowed deleting 'Self' member!" -ForegroundColor Red; exit 1
} catch {
    Write-Host "[5/10] Successfully blocked deletion of default 'Self' member" -ForegroundColor Green
}

# 6. Soft-delete Grandma Mary
Invoke-RestMethod -Uri "$baseUrl/api/family-members/$($createdMember.id)" -Method Delete -Headers $cgHeaders
$afterDeleteMembers = Invoke-RestMethod -Uri "$baseUrl/api/family-members" -Method Get -Headers $cgHeaders
if (-not ($afterDeleteMembers | Where-Object { $_.id -eq $createdMember.id })) {
    Write-Host "[6/10] Soft-deleted member excluded from listing successfully" -ForegroundColor Green
} else {
    Write-Host "[6/10] FAILED: Soft-deleted member still visible." -ForegroundColor Red; exit 1
}

# 7. Register Recipient
$recipientEmail = "recipient_p2_" + (Get-Random) + "@carevoice.app"
$recBody = @{
    Email = $recipientEmail
    Password = "Password123!"
    FullName = "Phase 2 Recipient"
    PhoneNumber = "+1122334455"
} | ConvertTo-Json

$recReg = Invoke-RestMethod -Uri "$baseUrl/api/auth/register" -Method Post -Body $recBody -ContentType "application/json"
$recToken = $recReg.accessToken
$recHeaders = @{ Authorization = "Bearer $recToken" }
Write-Host "[7/10] Recipient registered: $recipientEmail" -ForegroundColor Green

# 8. Caregiver creates an invitation for Recipient
$inviteBody = @{
    InvitedEmail = $recipientEmail
    CanSetReminders = $true
    CanViewLogs = $true
} | ConvertTo-Json

$invite = Invoke-RestMethod -Uri "$baseUrl/api/invites" -Method Post -Headers $cgHeaders -Body $inviteBody -ContentType "application/json"
$inviteToken = $invite.inviteToken
Write-Host "[8/10] Caregiver generated invite token: $inviteToken" -ForegroundColor Green

# 9. Recipient accepts invitation
$acceptBody = @{
    InviteToken = $inviteToken
} | ConvertTo-Json

$acceptRes = Invoke-RestMethod -Uri "$baseUrl/api/invites/accept" -Method Post -Headers $recHeaders -Body $acceptBody -ContentType "application/json"
Write-Host "[9/10] Recipient accepted invite: $($acceptRes.message)" -ForegroundColor Green

# 10. Verify FamilyPermissions linkage
$cgMembersAfterLink = Invoke-RestMethod -Uri "$baseUrl/api/family-members" -Method Get -Headers $cgHeaders
$linkedRecipient = $cgMembersAfterLink | Where-Object { $_.fullName -eq "Phase 2 Recipient" }
if ($linkedRecipient -and $linkedRecipient.canSetReminders -eq $true -and $linkedRecipient.canViewLogs -eq $true) {
    Write-Host "[10/10] Caregiver can now access Recipient with CanSetReminders and CanViewLogs permissions!" -ForegroundColor Green
} else {
    Write-Host "[10/10] FAILED: Linkage not found or permissions missing." -ForegroundColor Red; exit 1
}

Write-Host "=== ALL 10 PHASE 2 BACKEND CHECKS PASSED SUCCESSFULLY ===" -ForegroundColor Green
