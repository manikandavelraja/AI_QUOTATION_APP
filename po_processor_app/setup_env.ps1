# PowerShell script to set up environment variables
# This script helps you create a .env file from the .env.example template

Write-Host "=== Environment Variables Setup ===" -ForegroundColor Green
Write-Host ""

$envFile = ".env"
$exampleFile = ".env.example"

# Check if .env.example exists
if (-not (Test-Path $exampleFile)) {
    Write-Host "Error: .env.example file not found!" -ForegroundColor Red
    Write-Host "Please create .env.example first." -ForegroundColor Yellow
    exit 1
}

# Check if .env already exists
if (Test-Path $envFile) {
    Write-Host "⚠️  Warning: .env file already exists!" -ForegroundColor Yellow
    $overwrite = Read-Host "Do you want to overwrite it? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Copy .env.example to .env
Copy-Item $exampleFile $envFile -Force
Write-Host "✅ Created .env file from .env.example" -ForegroundColor Green
Write-Host ""

# Prompt for API keys
Write-Host "Now you need to fill in your actual API keys in the .env file." -ForegroundColor Cyan
Write-Host ""

# Get Gemini API Key
Write-Host "Gemini API Key:" -ForegroundColor Yellow
Write-Host "  Get it from: https://makersuite.google.com/app/apikey" -ForegroundColor Gray
$geminiKey = Read-Host "  Enter your Gemini API Key (or press Enter to skip)"
if ($geminiKey -ne "") {
    (Get-Content $envFile) -replace 'GEMINI_API_KEY=your_gemini_api_key_here', "GEMINI_API_KEY=$geminiKey" | Set-Content $envFile
    Write-Host "  ✅ Gemini API Key saved" -ForegroundColor Green
}

Write-Host ""

# Get Gmail Client ID
Write-Host "Gmail OAuth2 Client ID (optional for now):" -ForegroundColor Yellow
Write-Host "  Get it from: https://console.cloud.google.com/" -ForegroundColor Gray
$gmailClientId = Read-Host "  Enter your Gmail Client ID (or press Enter to skip)"
if ($gmailClientId -ne "") {
    (Get-Content $envFile) -replace 'GMAIL_WEB_CLIENT_ID=your_gmail_oauth2_client_id_here', "GMAIL_WEB_CLIENT_ID=$gmailClientId" | Set-Content $envFile
    Write-Host "  ✅ Gmail Client ID saved" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Edit .env file to add any remaining values" -ForegroundColor White
Write-Host "2. Run: flutter pub get" -ForegroundColor White
Write-Host "3. Run: flutter run" -ForegroundColor White
Write-Host ""
Write-Host "⚠️  IMPORTANT: Never commit .env to Git!" -ForegroundColor Yellow
Write-Host "   The .env file is already in .gitignore" -ForegroundColor Gray

