# Multi-GitHub Identity Setup

> **Manage multiple GitHub accounts (work, personal, open source) on a single machine with automatic identity switching.**

---

## 🧠 The Problem

If you contribute to GitHub using multiple accounts — say, a **work** account (`you@company.com`), a **personal** account (`you@gmail.com`), and an **open source** org account — you've likely experienced:

- Committing to a work repo with your personal email (and vice versa)
- Constantly remembering to run `git config user.name` and `git config user.email` in each repo
- Juggling multiple SSH keys and figuring out which one to use
- Awkward `git push` errors because the wrong SSH key or token is used

---

## ✅ The Solution

Three layers working together:

| Layer | What it does |
|---|---|
| **SSH host aliases** (`~/.ssh/config`) | Routes each GitHub alias (e.g. `github.com-work`) to a specific SSH private key |
| **Git config includes** (`~/.gitconfig-*`) | Stores the `[user]` name/email for each profile |
| **Git conditional includes** (`~/.gitconfig`) | Auto-applies the right identity based on the remote URL |

**The result:** You clone/push as usual — Git automatically picks the correct SSH key AND commit identity based on the repo's remote URL. No manual switching. No accidental cross-account commits.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                   ~/.gitconfig                       │
│  ┌─────────────────────────────────────────────┐    │
│  │ [user]                                      │    │
│  │     name = <fallthrough>  ← used when no    │    │
│  │     email = <fallthrough>    identity file  │    │
│  │                              matches        │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │ [includeIf]  git@github.com-work:*/**       │────┼──→ ~/.gitconfig-work
│  │ [includeIf]  git@github.com-personal:*/**   │────┼──→ ~/.gitconfig-personal
│  │ [includeIf]  git@github.com-opensource:*/** │────┼──→ ~/.gitconfig-opensource
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                   ~/.ssh/config                      │
│  Host github.com-work     → IdentityFile ~/.ssh/id_work │
│  Host github.com-personal → IdentityFile ~/.ssh/id_personal │
│  Host github.com-opensource → IdentityFile ~/.ssh/id_opensource │
└─────────────────────────────────────────────────────┘

You clone with:   git clone git@github.com-work:org/repo.git
                              ^^^^^^^^^^^^^^^^^
                              SSH picks key    Git picks identity
```

---

## 🚀 Quick Start

### Prerequisites

- **Git** (2.30+ recommended for `includeIf` support)
- **SSH** (OpenSSH, pre-installed on macOS/Linux)
- **GitHub account(s)** — one per profile

### One-shot setup (recommended)

```bash
git clone git@github.com:daivahealth/multi-git-identity-setup.git
cd multi-git-identity-setup
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The script will prompt you for each profile and handle everything:

| Step | What it does |
|---|---|
| 1 | Generates an ed25519 SSH key pair |
| 2 | Adds a host alias to `~/.ssh/config` |
| 3 | Creates a `~/.gitconfig-<profile>` with your name/email |
| 4 | Adds `[includeIf]` to `~/.gitconfig` to auto-apply the identity |

Run it once per profile. After that, add more with:

```bash
./scripts/add-identity.sh
```

### Manual setup

If you prefer to configure everything by hand, follow the steps below.

---

## 📋 Manual Setup Guide

### Step 1: Generate SSH keys

Create one SSH key pair per identity:

```bash
# Personal account
ssh-keygen -t ed25519 -C "your.personal@gmail.com" -f ~/.ssh/id_personal -N ""

# Work account
ssh-keygen -t ed25519 -C "you@company.com" -f ~/.ssh/id_work -N ""

# Open source / org account
ssh-keygen -t ed25519 -C "you@opensource.org" -f ~/.ssh/id_opensource -N ""
```

Add each public key to the corresponding GitHub account:

1. Open `https://github.com/settings/keys`
2. Click **New SSH Key**
3. Paste the contents of `~/.ssh/id_<profile>.pub`
4. Repeat for each account

### Step 2: Configure SSH (`~/.ssh/config`)

```bash
# ~/.ssh/config

# ── Work identity ───────────────────────────────────────
Host github.com-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_work

# ── Personal identity ────────────────────────────────────
Host github.com-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_personal

# ── Open Source / Organization identity ──────────────────
Host github.com-opensource
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_opensource

# ── Default (fallback) ───────────────────────────────────
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_personal
```

> **Important:** The `Host` value (e.g., `github.com-work`) is an alias, not the real hostname. SSH uses it to match against the remote URL you provide. The `HostName github.com` tells SSH where to actually connect.

### Step 3: Create identity-specific gitconfig files

```bash
# ~/.gitconfig-personal
[user]
    name = Your Personal Name
    email = your.personal@gmail.com

# ~/.gitconfig-work
[user]
    name = Your Work Name
    email = you@company.com

# ~/.gitconfig-opensource
[user]
    name = Your Org Name
    email = you@opensource.org
```

### Step 4: Set up conditional includes (`~/.gitconfig`)

This is the **key piece**. Git's `includeIf` directive conditionally loads a config file based on the repo's remote URL pattern.

```bash
# ~/.gitconfig (global)

# ── Fall-through identity (used when no includeIf matches) ──
[user]
    name = Your Name
    email = your.default@email.com

# ── Identity overrides (MUST come AFTER the [user] block above) ──
[includeIf "hasconfig:remote.*.url:git@github.com-work:*/**"]
    path = ~/.gitconfig-work

[includeIf "hasconfig:remote.*.url:git@github.com-personal:*/**"]
    path = ~/.gitconfig-personal

[includeIf "hasconfig:remote.*.url:git@github.com-opensource:*/**"]
    path = ~/.gitconfig-opensource
```

> **Why the pattern `git@github.com-<profile>:*/**`?**
> - `*` matches a single path segment (e.g., the org name `org`)
> - `**` matches the rest of the path (e.g., `repo.git`)
> - The `/` between them triggers Git's `WM_PATHNAME` semantics for wildmatch, ensuring correct matching on SSH-style URLs

> **Why must `includeIf` come AFTER `[user]`?**
> Git applies settings **last-write-wins**. The `includeIf` needs to load _after_ the fallthrough `[user]` block so it overrides it.

---

## 🧪 Verification

Make sure everything works:

```bash
# Test SSH connection for each profile
ssh -T git@github.com-work      # → "Hi <work-username>! You've successfully authenticated..."
ssh -T git@github.com-personal  # → "Hi <personal-username>! You've successfully authenticated..."
ssh -T git@github.com-opensource # → "Hi <opensource-username>! You've successfully authenticated..."

# Clone a work repo and verify identity
git clone git@github.com-work:your-org/work-repo.git
cd work-repo
git config user.name   # Should show your work name
git config user.email  # Should show your work email

# Clone a personal repo and verify identity
git clone git@github.com-personal:your-name/personal-repo.git
cd personal-repo
git config user.name   # Should show your personal name
git config user.email  # Should show your personal email

# Make a test commit
echo "test" > test.txt
git add test.txt
git commit -m "test: verify identity"
git log --format="%an <%ae>" -1  # Should show the correct identity
```

---

## 🔧 Day-to-Day Usage

### Cloning a NEW repository

Use the profile alias in the remote URL:

```bash
# Work repo
git clone git@github.com-work:acme-inc/backend.git

# Personal repo
git clone git@github.com-personal:myuser/pet-project.git

# Open source repo (where you're a contributor)
git clone git@github.com-opensource:some-org/library.git
```

### Updating an EXISTING repository

If you already have a repo cloned with `git@github.com:...`, update its remote:

```bash
cd /path/to/repo

# Check current remote
git remote -v

# Update to use the profile alias
git remote set-url origin git@github.com-work:org/repo.git

# Verify identity is now correct
git config user.name
git config user.email
```

The `includeIf` is evaluated **dynamically** — every `git` command re-reads the config based on the current remote URL. No need to re-clone.

### Adding a new identity later

```bash
# If you used the setup script:
./scripts/add-identity.sh

# Or manually: repeat Steps 1-4 with a new profile name
```

---

## ⚙️ Advanced

### Hardening: fail on missing identity

Once every repo you care about matches an `includeIf` rule, you can make Git refuse to commit when the identity is unresolved:

```bash
# In ~/.gitconfig (at the bottom)
[user]
    useConfigOnly = true
```

This prevents accidental commits using the fallthrough identity.

### GitHub CLI (gh) with multiple accounts

The `gh` CLI supports multiple accounts. You can authenticate with each:

```bash
gh auth login -h github.com
# → Select your first account
gh auth login -h github.com
# → Select your second account
```

Then switch between them:

```bash
gh auth switch -u <username>
```

Check which is active:

```bash
gh auth status
```

> **Note:** The `gh` CLI's credential helper (`gh auth git-credential`) handles HTTPS git operations. If you use SSH (as this guide recommends), the SSH key handles auth and `gh` is used for PRs, issues, etc.

### Windows users

Replace `~/.ssh/config` with `%USERPROFILE%\.ssh\config` and `~/.gitconfig` with `%USERPROFILE%\.gitconfig`. The configuration content is identical — Git on Windows uses the same config format and `includeIf` syntax.

### Using different email for private commits

GitHub allows you to keep your email private. If you enable "Keep my email addresses private" in GitHub settings, use the `@users.noreply.github.com` email in your gitconfig:

```bash
[user]
    name = Your Name
    email = your-username@users.noreply.github.com
```

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | SSH key not added to GitHub account | Upload `~/.ssh/id_<profile>.pub` to GitHub |
| Wrong name/email on commits | Remote URL doesn't match any `includeIf` pattern | Run `git remote -v` and update with `git remote set-url origin git@github.com-<profile>:org/repo.git` |
| `Could not read from remote repository` | Wrong SSH key being used | Check `~/.ssh/config` — ensure the `Host` alias matches your remote URL |
| `git push` asks for password | Remote URL uses HTTPS instead of SSH | Update remote: `git remote set-url origin git@github.com-<profile>:org/repo.git` |
| Commits attributed to wrong account | Email in gitconfig doesn't match GitHub's verified emails | Update the correct `~/.gitconfig-<profile>` file, or add the email to your GitHub account |
| `includeIf` not working | Pattern doesn't match | Ensure the pattern uses `*/**` with a slash separator: `git@github.com-work:*/**` |

### Debugging: trace which identity Git is using

```bash
# See the resolved config for a repo
git config --includes user.name
git config --includes user.email

# Debug SSH's key selection
GIT_SSH_COMMAND="ssh -v" git fetch 2>&1 | grep "Offering public key"

# See which includeIf rules are active
git config --list --show-origin | grep includeIf
```

---

## 🤝 Contributing

Found a bug? Want to add a feature? PRs welcome!

1. Fork the repo
2. Create your feature branch: `git checkout -b feature/amazing`
3. Commit with your personal identity
4. Push: `git push origin feature/amazing`
5. Open a Pull Request

---

## 📄 License

MIT — free for anyone to use, modify, and share.

---

## 🙏 Credits

Built from real-world experience managing three GitHub accounts across personal projects, open-source contributions, and enterprise work.
