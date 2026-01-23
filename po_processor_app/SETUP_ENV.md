# Environment Variables Setup Guide

## ⚠️ Security Notice

**IMPORTANT**: Your API keys and secrets should NEVER be committed to version control. This guide will help you set up secure environment variable management.

## Quick Setup

1. **Copy the example file:**
   ```bash
   cd po_processor_app
   cp .env.example .env
   ```

2. **Edit `.env` file** and add your actual API keys:
   ```env
   GEMINI_API_KEY=your_actual_gemini_api_key_here
   GEMINI_MODEL=gemini-2.5-flash
   GMAIL_WEB_CLIENT_ID=your_gmail_oauth2_client_id_here
   EMAIL_ADDRESS=your_email@example.com
   ENCRYPTION_KEY=your_secure_encryption_key_here
   ```

3. **Verify `.env` is in `.gitignore`:**
   - The `.env` file should already be ignored by Git
   - Never commit `.env` to the repository

## Getting Your API Keys

### Gemini API Key

1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the key and paste it into your `.env` file

### Gmail OAuth2 Client ID

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Gmail API
4. Go to "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Select "Web application"
6. Add authorized JavaScript origins: `http://localhost:PORT` (for local development)
7. Add authorized redirect URIs: `http://localhost:PORT`
8. Copy the Client ID and paste it into your `.env` file

## Running the App

After setting up your `.env` file:

```bash
flutter pub get
flutter run
```

## Troubleshooting

### Error: "GEMINI_API_KEY not found in environment variables"

**Solution**: Make sure:
1. The `.env` file exists in the `po_processor_app` directory
2. The `.env` file contains `GEMINI_API_KEY=your_key`
3. You've run `flutter pub get` after adding `flutter_dotenv`
4. The `.env` file is listed in `pubspec.yaml` under `assets`

### Error: "Could not load .env file"

**Solution**: 
- Check that `.env` file is in the correct location (`po_processor_app/.env`)
- Verify the file name is exactly `.env` (not `.env.txt` or similar)
- Make sure there are no syntax errors in the `.env` file

## For Production

For production deployments:

1. **Never use `.env` files in production**
2. Use your platform's secure secret management:
   - **Firebase**: Use Firebase Remote Config or Functions environment variables
   - **AWS**: Use AWS Secrets Manager or Parameter Store
   - **Google Cloud**: Use Secret Manager
   - **Heroku**: Use Config Vars
   - **Docker**: Use environment variables or Docker secrets

3. **Rotate your keys** if they were ever committed to Git:
   - Generate new API keys immediately
   - Revoke the old keys
   - Update your `.env` file with new keys

## Security Best Practices

1. ✅ Use `.env` files for local development only
2. ✅ Add `.env` to `.gitignore` (already done)
3. ✅ Never commit API keys to version control
4. ✅ Rotate keys if accidentally committed
5. ✅ Use different keys for development and production
6. ✅ Limit API key permissions in Google Cloud Console
7. ✅ Monitor API usage for suspicious activity

## Verifying Your Setup

To verify your environment variables are loaded correctly, check the console output when running the app. You should see:

```
✅ Environment variables loaded successfully
```

If you see a warning, check the troubleshooting section above.

