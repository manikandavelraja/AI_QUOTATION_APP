# Simple Flutter Web Build and Run Script
# Alternative script with minimal cleanup

Write-Host "Building and launching Flutter web application..." -ForegroundColor Green

# Navigate to the Flutter app directory
Set-Location -Path "po_processor_app"

# Run flutter clean first to remove build artifacts
Write-Host "Cleaning Flutter build..." -ForegroundColor Cyan
flutter clean

# Get dependencies
Write-Host "Getting Flutter dependencies..." -ForegroundColor Cyan
flutter pub get

# Run the app
Write-Host "Starting Flutter web app on Chrome..." -ForegroundColor Green
flutter run -d chrome --web-port=8080


