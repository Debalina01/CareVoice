# ==============================================================================
# CareVoice - Free Firebase Hosting & Firestore Cloud Deployment Script
# ==============================================================================
# Prerequisites:
# 1. Install Firebase CLI: npm install -g firebase-tools
# 2. Login to Firebase: firebase login
# 3. Create a free Firebase project at: https://console.firebase.google.com
# 4. Link your project: firebase use --add <your-project-id>
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CareVoice - Free Firebase Hosting & Cloud Sync Deploy" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Flutter & Firebase CLI
Write-Host "`n[1/3] Checking dependencies..." -ForegroundColor Yellow
$flutterPath = "D:\DevTools\flutter\bin"
if (Test-Path "$flutterPath\flutter.bat") {
    $env:PATH = "$flutterPath;$env:PATH"
}

$firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebaseCmd) {
    Write-Host "Warning: 'firebase' command not found in PATH." -ForegroundColor Red
    Write-Host "Please install it with: npm install -g firebase-tools" -ForegroundColor White
} else {
    Write-Host "Firebase CLI found at: $($firebaseCmd.Source)" -ForegroundColor Green
}

# 2. Build Flutter Web release
Write-Host "`n[2/3] Building Flutter Web for production..." -ForegroundColor Yellow
Set-Location "mobile\carevoice_app"
flutter build web --release --no-tree-shake-icons

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter web build failed!" -ForegroundColor Red
    Set-Location "..\.."
    exit $LASTEXITCODE
}

Set-Location "..\.."
Write-Host "Flutter Web build completed: mobile/carevoice_app/build/web" -ForegroundColor Green

# 3. Deploy to Firebase Hosting (Spark Plan - 100% Free)
Write-Host "`n[3/3] Deploying to Firebase Hosting (100% Free Spark Tier)..." -ForegroundColor Yellow
if ($firebaseCmd) {
    firebase deploy --only hosting,firestore
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n==========================================================" -ForegroundColor Green
        Write-Host " CareVoice successfully deployed to Firebase Free Hosting!" -ForegroundColor Green
        Write-Host " Real-time Family Sharing is active on Cloud Firestore!" -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
    } else {
        Write-Host "`nTo deploy, link your project first with: firebase use --add <project-id>" -ForegroundColor Yellow
        Write-Host "Then run: firebase deploy --only hosting" -ForegroundColor Cyan
    }
} else {
    Write-Host "Skipping auto-deploy because Firebase CLI was not found." -ForegroundColor Yellow
}
