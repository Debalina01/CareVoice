$body = @{
    Email = "caregiver@carevoice.app"
    Password = "Password123!"
} | ConvertTo-Json

try {
    $res = Invoke-RestMethod -Uri "http://localhost:5070/api/auth/login" -Method Post -Body $body -ContentType "application/json"
    Write-Host "LOGIN SUCCESS! User:" $res.user.fullName "Email:" $res.user.email
    Write-Host "Access Token received:" ($res.accessToken.Substring(0, 30) + "...")
} catch {
    Write-Host "LOGIN FAILED:" $_.Exception.Message
}
