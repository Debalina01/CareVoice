$email = "user.$(Get-Random)@carevoice.app"
$password = "Password123!"

$regBody = @{
    Email = $email
    Password = $password
    FullName = "Test Caregiver User"
    PhoneNumber = "+19998887777"
} | ConvertTo-Json

Write-Host "1. Testing POST /api/auth/register..."
$regRes = Invoke-RestMethod -Uri "http://localhost:5070/api/auth/register" -Method Post -Body $regBody -ContentType "application/json"
Write-Host "   [SUCCESS] Register Token:" ($regRes.accessToken.Substring(0, 30) + "...")
Write-Host "   [SUCCESS] User ID:" $regRes.user.id
Write-Host "   [SUCCESS] Default FamilyMember ID:" $regRes.user.defaultFamilyMemberId

$loginBody = @{
    Email = $email
    Password = $password
} | ConvertTo-Json

Write-Host "`n2. Testing POST /api/auth/login..."
$loginRes = Invoke-RestMethod -Uri "http://localhost:5070/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json"
Write-Host "   [SUCCESS] Login Token:" ($loginRes.accessToken.Substring(0, 30) + "...")
Write-Host "   [SUCCESS] Refresh Token:" ($loginRes.refreshToken.Substring(0, 30) + "...")

$refreshBody = @{
    AccessToken = $loginRes.accessToken
    RefreshToken = $loginRes.refreshToken
} | ConvertTo-Json

Write-Host "`n3. Testing POST /api/auth/refresh..."
$refreshRes = Invoke-RestMethod -Uri "http://localhost:5070/api/auth/refresh" -Method Post -Body $refreshBody -ContentType "application/json"
Write-Host "   [SUCCESS] Refreshed Access Token:" ($refreshRes.accessToken.Substring(0, 30) + "...")
Write-Host "   [SUCCESS] Refreshed Refresh Token:" ($refreshRes.refreshToken.Substring(0, 30) + "...")
