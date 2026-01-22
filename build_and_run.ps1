# Flutter Web Build and Run Script
# This script builds the Flutter web app and automatically opens it in the browser

Write-Host "Building and launching Flutter web application..." -ForegroundColor Green

# Navigate to the Flutter app directory
Set-Location -Path "po_processor_app"

# Function to safely remove build directory
function Remove-BuildDirectory {
    param([string]$Path)
    
    if (Test-Path $Path) {
        Write-Host "Attempting to clean build directory: $Path" -ForegroundColor Yellow
        
        # Try to remove files with retry logic
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        
        while ($retryCount -lt $maxRetries -and -not $success) {
            try {
                # Close any processes that might be locking files
                Get-Process | Where-Object { $_.Path -like "*$Path*" } | Stop-Process -Force -ErrorAction SilentlyContinue
                
                # Wait a moment for file handles to release
                Start-Sleep -Milliseconds 500
                
                # Remove directory recursively with force
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
                $success = $true
                Write-Host "Successfully removed build directory" -ForegroundColor Green
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Retry $retryCount of $maxRetries - Waiting before retry..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
                else {
                    Write-Host "Warning: Could not remove $Path. Flutter clean will handle it." -ForegroundColor Yellow
                }
            }
        }
    }
}

# Clean build directories before running
Write-Host "Cleaning build directories..." -ForegroundColor Cyan
$buildPath = Join-Path $PWD "build"
$flutterAssetsPath = Join-Path $buildPath "flutter_assets"

Remove-BuildDirectory -Path $flutterAssetsPath

# Run flutter clean to ensure a fresh build
Write-Host "Running flutter clean..." -ForegroundColor Cyan
flutter clean

# Get dependencies
Write-Host "Getting Flutter dependencies..." -ForegroundColor Cyan
flutter pub get

# Use Flutter's Chrome device which builds and automatically opens Chrome
# This will build the app, start a local server, and open Chrome automatically
Write-Host "Starting Flutter web app on Chrome..." -ForegroundColor Green
flutter run -d chrome --web-port=8080

