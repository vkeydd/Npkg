# npkg 📦

`npkg` is a lightweight, zero-dependency, system-wide package manager written in **Nim**, designed with the Unix philosophy in mind. It allows you to effortlessly install and manage GitHub-hosted binary tools and scripts without dealing with bloated runtimes or complex dependency trees.

## ✨ Features

- **Zero-Dependency Architecture:** Bypasses heavy frameworks and SSL complexities by leveraging core Unix tools (`curl`, `tar`, `ln`).
- **Smart Branch Resolution:** Automatically detects and falls back between `main` and `master` branches.
- **Automatic Permissions & Symlinking:** Automatically grants execution permissions (`chmod +x`) and links binaries directly to `/usr/local/bin/` for instant system-wide availability.
- **Flexible Binary Discovery:** Scans repository roots and subdirectories (`bin/`, etc.) to locate executables automatically.
- **Clean Installation & Removal:** Managed via a traditional `Makefile` and includes robust cleanup for both package files and symlinks.

---

##  Why Nim?👑️

You might wonder why **Nim** was chosen to build `npkg` instead of Shell, Python, or Go. Here is why Nim is the ideal tool for system-level utilities:

- **Native Performance & C-like Speed:** Nim compiles directly to efficient C/C++, meaning `npkg` executes instantly with zero startup lag or interpreter overhead.
- **True Single-Binary Output:** It compiles into a completely standalone, native binary with zero runtime dependencies. You don't need to install interpreters, virtual environments, or heavy runtimes on target machines.
- **Clean, Expressive Syntax:** Nim offers Python-like readability while giving you low-level system control, making the codebase compact, readable, and easy to maintain.
- **Powerful System Integration:** Its standard library provides robust and clean primitives for handling file systems, executing shell commands, and managing processes.

---

## 🚀 Installation

### Prerequisites
Make sure you have the following tools installed on your system:
- [Nim Compiler](https://nim-lang.org/)
- `curl`
- `tar`

### Building from Source with GNU Make(recomended)
```
git clone https://github.com/vkeydd/Npkg.git
cd npkg

# Build the release binary
make

# Install system-wide (requires root privileges)
sudo make install
```
---
### Or using nimble
``` 
git clone https://github.com/vkeydd/Npkg.git
cd Npkg
# Then instal with Nimble
sudo nimble install
``` 
## 💡 Usage

Once installed, you can manage packages using straightforward commands:

### Add a Package
Installs a repository system-wide (downloads, extracts, sets permissions, and symlinks):
```
sudo npkg add dylanaraps/pfetch
```

### Remove a Package
Completely removes the package directory from `/opt/npkg/` and cleans up its symlink from `/usr/local/bin/`:
```
sudo npkg remove neofetch
```

---

## 📂 Directory Structure

`npkg` organizes files cleanly adhering to standard Unix filesystem hierarchies:

- **Package Storage:** `/opt/npkg/<package-name>`
- **Global Executables:** `/usr/local/bin/<package-name>`
- **Registry:** Maintained locally to track installed packages.

---

## 📜 License

This project is open-source and available under the [MIT License](LICENSE).
