$body = @{
    Email = "caregiver@carevoice.app"
    Password = "Password123!"
    FullName = "Primary Caregiver"
    PhoneNumber = "+1234567890"
} | ConvertTo-Json

try {
    $res = Invoke-RestMethod -Uri "http://localhost:5070/api/auth/register" -Method Post -Body $body -ContentType "application/json"
    Write-Host "Created account: $($res.user.email)"
} catch {
    Write-Host "Account status: $($_.Exception.Message)"
}
