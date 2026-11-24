# Vercel settings and first administrator

The private `vercel/.env` file contains all deployment variables, a generated setup token, and your initial administrator credentials. It is excluded from Git and function uploads. `.env.example` is the shareable template.

1. Fill `DATABASE_URL` in `.env` with your real hosted PostgreSQL URL, including `sslmode=require`. This is the only required value that could not be generated for you.
2. In Vercel, open your project -> Settings -> Environment Variables and add the values from `.env` to Production. Keep the project root at the repository root, not this folder. Do not add `VERCEL` or `API_BASE_URL` manually.
3. Deploy/redeploy. The build creates the initial administrator automatically from `INITIAL_ADMIN_EMAIL`, `INITIAL_ADMIN_PASSWORD`, and `INITIAL_ADMIN_NAME` if the database has no administrator yet.
4. Open `https://YOUR-PROJECT.vercel.app/#/login` and sign in with the email/password in `.env`. Your user ID for login is the email. The internal first-admin ID is `initial-admin`.

Automatic setup never changes an existing administrator's password, promotes an existing student, or recreates the account on later deployments. After first setup, remove `INITIAL_ADMIN_PASSWORD` from Vercel and redeploy; use Profile to change your password when desired.

Manual setup remains available at `/#/setup` when no administrator exists. It requires `ADMIN_SETUP_TOKEN` and lets you choose your own email/password. When setup is already complete, this route opens sign-in.

For a new local database, create the same initial account using:

```powershell
.tools\venv\Scripts\python.exe -m backend.manage bootstrap-admin --env-file vercel/.env
```

This command reads **only administrator credentials** from this deployment file. It continues using your normal local database settings; it does not apply `COOKIE_SECURE=true` or silently switch the local app to your hosted database.

Local sign-in: `http://127.0.0.1:8080/#/login`. Local manual setup: `http://127.0.0.1:8080/#/setup`.

`APP_ORIGIN` and `CAMPUS_CIDRS` are optional and can remain empty. `COOKIE_SECURE=true` is for HTTPS hosting; Vercel also enables secure cookies automatically. Use a separate database and separate administrator credentials for Preview deployments.
