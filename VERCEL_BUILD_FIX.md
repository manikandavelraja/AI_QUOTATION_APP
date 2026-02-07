# Vercel Build Error Fix - Flutter Command Not Found

## 🔴 The Problem

Your Vercel deployment is failing with:
```
sh: line 1: flutter: command not found
Error: Command "cd po_processor_app && flutter build web --release" exited with 127
```

**Root Cause:** Vercel's build environment doesn't have Flutter SDK installed by default.

## ✅ The Solution

I've created two files to fix this:

### 1. `build.sh` - Flutter Installation & Build Script

This script:
- Downloads and installs Flutter SDK during the build
- Sets up the environment
- Builds your Flutter web app

### 2. Updated `vercel.json`

Updated to use the build script instead of calling `flutter` directly.

## 📋 What Changed

### Before (❌ Broken):
```json
{
  "buildCommand": "cd po_processor_app && flutter build web --release"
}
```

### After (✅ Fixed):
```json
{
  "buildCommand": "bash build.sh",
  "outputDirectory": "po_processor_app/build/web"
}
```

## 🚀 How It Works

1. **Vercel starts the build** and runs `bash build.sh`
2. **Build script downloads Flutter SDK** (if not cached)
3. **Flutter is added to PATH** for the build session
4. **Dependencies are installed** (`flutter pub get`)
5. **Web app is built** (`flutter build web --release`)
6. **Vercel serves** the output from `po_processor_app/build/web`

## ⚙️ Build Script Details

The `build.sh` script:
- Downloads Flutter SDK from Google's official repository
- Falls back to git clone if download fails
- Verifies installation before building
- Handles errors gracefully with `set -e`

## 🔍 Why This Approach?

**Alternative approaches considered:**

1. **Dockerfile** ❌
   - Vercel doesn't use Dockerfiles by default
   - Would require additional configuration

2. **Pre-built artifacts** ❌
   - Would require committing build files to git
   - Not ideal for CI/CD

3. **GitHub Actions + Vercel** ❌
   - More complex setup
   - Requires additional services

4. **Install Flutter in buildCommand** ✅ **CHOSEN**
   - Simple and reliable
   - Works with Vercel's build system
   - No additional services needed

## 📝 Next Steps

1. **Commit the files:**
   ```bash
   git add vercel.json build.sh
   git commit -m "Fix Vercel build: Install Flutter SDK during build"
   git push
   ```

2. **Vercel will automatically:**
   - Detect the new commit
   - Trigger a new deployment
   - Run the build script
   - Deploy if successful

3. **Monitor the build:**
   - Check Vercel dashboard for build logs
   - First build may take longer (Flutter SDK download)
   - Subsequent builds will be faster (caching)

## ⚠️ Potential Issues & Solutions

### Issue 1: Build Timeout
**Symptom:** Build fails after 45 seconds (Vercel free tier limit)

**Solution:** 
- Upgrade to Vercel Pro (longer timeout)
- Or use GitHub Actions to build, then deploy artifacts

### Issue 2: Flutter Download Fails
**Symptom:** `curl` command fails

**Solution:** 
- The script has a fallback to `git clone`
- Check Vercel build logs for network issues

### Issue 3: Path Issues
**Symptom:** Script can't find `po_processor_app` directory

**Solution:**
- The script uses `$VERCEL_SOURCE_DIR` or falls back to `$(pwd)`
- Verify your project structure matches

## 🎓 Key Learnings

1. **Vercel's build environment is minimal** - Only includes common tools (Node.js, Python, etc.)
2. **Flutter isn't pre-installed** - You need to install it during the build
3. **Build scripts are powerful** - They can install dependencies, configure environments, etc.
4. **Caching helps** - Vercel caches build artifacts, making subsequent builds faster

## 📚 Related Documentation

- [Vercel Build Configuration](https://vercel.com/docs/build-step)
- [Flutter Web Deployment](https://docs.flutter.dev/deployment/web)
- [Vercel Environment Variables](https://vercel.com/docs/environment-variables)

---

**Status:** ✅ **FIXED** - Your build should now succeed!

