# PowerShell script to push project to GitHub
# Make sure Git is installed and you have GitHub credentials configured

Write-Host "=== Pushing AI Quotation App to GitHub ===" -ForegroundColor Green

# Navigate to project directory
Set-Location "c:\OurProjects\AIPoweredApplication"

# Check if git is initialized
if (-not (Test-Path .git)) {
    Write-Host "Initializing Git repository..." -ForegroundColor Yellow
    git init
}

# Check if remote already exists
$remoteExists = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Adding remote repository..." -ForegroundColor Yellow
    git remote add origin https://github.com/manikandavelraja/AI_QUOTATION_APP.git
} else {
    Write-Host "Remote already exists: $remoteExists" -ForegroundColor Cyan
    Write-Host "Updating remote URL..." -ForegroundColor Yellow
    git remote set-url origin https://github.com/manikandavelraja/AI_QUOTATION_APP.git
}

# Add all files
Write-Host "Adding files to Git..." -ForegroundColor Yellow
git add .

# Commit changes
Write-Host "Committing changes..." -ForegroundColor Yellow
$commitMessage = "Initial commit: AI Quotation App with customer email extraction fixes"
git commit -m $commitMessage

# Check current branch
$currentBranch = git branch --show-current
if (-not $currentBranch) {
    Write-Host "Creating main branch..." -ForegroundColor Yellow
    git branch -M main
    $currentBranch = "main"
}

# Push to GitHub
Write-Host "Pushing to GitHub (branch: $currentBranch)..." -ForegroundColor Yellow
Write-Host "You may be prompted for your GitHub username and password/token." -ForegroundColor Cyan
git push -u origin $currentBranch

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=== Successfully pushed to GitHub! ===" -ForegroundColor Green
    Write-Host "Repository: https://github.com/manikandavelraja/AI_QUOTATION_APP.git" -ForegroundColor Cyan
} else {
    Write-Host "`n=== Push failed. Please check the error above. ===" -ForegroundColor Red
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "1. Git is not installed or not in PATH" -ForegroundColor Yellow
    Write-Host "2. GitHub credentials are not configured" -ForegroundColor Yellow
    Write-Host "3. Network connectivity issues" -ForegroundColor Yellow
    Write-Host "`nTo configure GitHub credentials, use:" -ForegroundColor Cyan
    Write-Host "git config --global user.name 'manikandavelraja'" -ForegroundColor White
    Write-Host "git config --global user.email 'your-email@example.com'" -ForegroundColor White
}

