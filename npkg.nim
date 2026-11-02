import std/[parseopt, os, strutils, json, uri, times, osproc]

when defined(posix):
  import posix

const 
  Version = "1.0.0"
  InstallDir = "/opt/npkg"
  RegistryFile = InstallDir / "registry.json"

# --- RENKLENDİRME (ANSI Escape Codes) ---
const
  Reset = "\e[0m"
  Red = "\e[31m"
  Green = "\e[32m"
  Yellow = "\e[33m"
  Blue = "\e[34m"
  Cyan = "\e[36m"
  Bold = "\e[1m"

proc printInfo(msg: string) = echo Cyan, "[INFO] ", Reset, msg
proc printSuccess(msg: string) = echo Green, "[SUCCESS] ", Reset, msg
proc printError(msg: string) = echo Red, "[ERROR] ", Reset, msg
proc printWarn(msg: string) = echo Yellow, "[WARN] ", Reset, msg

# --- ROOT YETKİ KONTROLÜ ---
proc ensureRoot() =
  when defined(posix):
    if geteuid() != 0:
      printError("System-wide operations require root privileges. Please run with 'sudo'.")
      quit(1)

# --- YEREL REGISTRY YÖNETİMİ ---
proc loadRegistry(): JsonNode =
  if fileExists(RegistryFile):
    try:
      result = parseJson(readFile(RegistryFile))
    except:
      result = newJObject()
  else:
    result = newJObject()

proc saveRegistry(node: JsonNode) =
  if not dirExists(InstallDir):
    createDir(InstallDir)
  writeFile(RegistryFile, $node)

# --- ARAMA (Curl + OSProc) - Yetki istemez ---
proc searchPackages(query: string) =
  printInfo("Searching for '" & query & "' across GitHub, GitLab, and Codeberg...")

  # 1. GitHub Search
  let ghUrl = "https://api.github.com/search/repositories?q=" & encodeUrl(query)
  let ghCmd = "curl -s -H \"User-Agent: npkg-manager\" " & quoteShell(ghUrl)
  let (ghResp, ghCode) = execCmdEx(ghCmd)
  
  echo "\n", Bold, "=== GitHub Results ===", Reset
  if ghCode == 0:
    try:
      let ghJson = parseJson(ghResp)
      if ghJson.hasKey("items"):
        for item in ghJson["items"]:
          if item.kind == JObject:
            echo "  * ", Cyan, item["full_name"].getStr(), Reset, " -> ", item["html_url"].getStr()
    except:
      echo "  (No results or parse error)"
  else:
    echo "  (GitHub search failed)"

  # 2. GitLab Search
  let glUrl = "https://gitlab.com/api/v4/projects?search=" & encodeUrl(query)
  let glCmd = "curl -s " & quoteShell(glUrl)
  let (glResp, glCode) = execCmdEx(glCmd)
  
  echo "\n", Bold, "=== GitLab Results ===", Reset
  if glCode == 0:
    try:
      let glJson = parseJson(glResp)
      if glJson.kind == JArray:
        for item in glJson:
          if item.hasKey("path_with_namespace") and item.hasKey("web_url"):
            echo "  * ", Cyan, item["path_with_namespace"].getStr(), Reset, " -> ", item["web_url"].getStr()
    except:
      echo "  (No results or parse error)"
  else:
    echo "  (GitLab search failed)"

  # 3. Codeberg Search
  let cbUrl = "https://codeberg.org/api/v1/repos/search?q=" & encodeUrl(query)
  let cbCmd = "curl -s " & quoteShell(cbUrl)
  let (cbResp, cbCode) = execCmdEx(cbCmd)
  
  echo "\n", Bold, "=== Codeberg Results ===", Reset
  if cbCode == 0:
    try:
      let cbJson = parseJson(cbResp)
      if cbJson.hasKey("data"):
        for item in cbJson["data"]:
          echo "  * ", Cyan, item["full_name"].getStr(), Reset, " -> ", item["html_url"].getStr()
    except:
      echo "  (No results or parse error)"
  else:
    echo "  (Codeberg search failed)"

# --- BAĞIMLILIK YÖNETİMİ ---
proc installDependencies(extractedPath: string) =
  let configPath = extractedPath / "pkg.json"
  if fileExists(configPath):
    try:
      let node = parseJson(readFile(configPath))
      if node.hasKey("requires") and node["requires"].kind == JArray:
        printInfo("Resolving dependencies...")
        for dep in node["requires"]:
          let depTarget = dep.getStr()
          printInfo("-> Dependency found: " & depTarget)
    except CatchableError as e:
      printWarn("Failed to parse pkg.json for dependencies: " & e.msg)

# --- İNDİRME VE KURULUM (Curl + Tar + Akıllı Dal Yönetimi) ---
proc downloadAndExtract(tarGzUrl, packageName: string) =
  ensureRoot()
  
  let tmpFile = getTempDir() / "npkg_temp.tar.gz"
  let targetDir = InstallDir / packageName

  try:
    printInfo("Downloading " & packageName & " from " & tarGzUrl)
    
    let curlCmd = "curl -L -s -o " & quoteShell(tmpFile) & " " & quoteShell(tarGzUrl)
    if execShellCmd(curlCmd) != 0:
      printError("Failed to download package using curl.")
      return

    if not dirExists(InstallDir):
      createDir(InstallDir)

    if dirExists(targetDir):
      removeDir(targetDir)
    createDir(targetDir)

    printInfo("Extracting package to " & targetDir & "...")
    
    let tarCmd = "tar -xzf " & quoteShell(tmpFile) & " -C " & quoteShell(targetDir) & " --strip-components=1"
    if execShellCmd(tarCmd) != 0:
      printError("Failed to extract package using tar.")
      return

    installDependencies(targetDir)

    var reg = loadRegistry()
    reg[packageName] = %* {
      "url": tarGzUrl,
      "installed_at": $now()
    }
    saveRegistry(reg)

    printSuccess("Successfully installed system-wide: " & packageName)
  except CatchableError as e:
    printError("Installation failed: " & e.msg)
  finally:
    if fileExists(tmpFile):
      removeFile(tmpFile)
# --- OTOMATİK İZİN VE PATH (SYMLINK) BAĞLAMA ---
    let globalBin = "/usr/local/bin" / packageName
    var foundBin = ""

    # Olası binary konumlarını sırayla kontrol et
    let candidate1 = targetDir / packageName
    let candidate2 = targetDir / "bin" / packageName

    if fileExists(candidate1):
      foundBin = candidate1
    elif fileExists(candidate2):
      foundBin = candidate2
    else:
      # Eğer net bulunamadıysa, dizindeki ilk çalıştırılabilir dosyayı bulmaya çalış
      for kind, path in walkDir(targetDir):
        if kind == pcFile and not path.endsWith(".md") and not path.endsWith(".json") and not path.endsWith(".txt"):
          foundBin = path
          break

    if foundBin != "" and fileExists(foundBin):
      discard execShellCmd("chmod +x " & quoteShell(foundBin))
      
      if fileExists(globalBin): removeFile(globalBin)
      let symCmd = "ln -s " & quoteShell(foundBin) & " " & quoteShell(globalBin)
      if execShellCmd(symCmd) == 0:
        printSuccess("Successfully linked " & packageName & " to /usr/local/bin/" & packageName)
      else:
        printWarn("Failed to create symlink for " & packageName)
    else:
      printWarn("Binary not found automatically. You can manually link it from: " & targetDir)
# --- GİRDİ ÇÖZÜMLEME VE AKILLI DAL YÖNETİMİ ---
proc addPackage(input: string) =
  var tarGzUrl = ""
  var packageName = ""

  if input.startsWith("http://") or input.startsWith("https://"):
    tarGzUrl = input
    packageName = extractFilename(input).replace(".tar.gz", "").replace(".tgz", "")
    if packageName == "":
      packageName = "custom_pkg"
    downloadAndExtract(tarGzUrl, packageName)
  elif input.contains("/"):
    let parts = input.split('/')
    if parts.len >= 2:
      let user = parts[0]
      let repo = parts[1]
      packageName = repo
      
      let mainUrl = "https://github.com/" & user & "/" & repo & "/archive/refs/heads/main.tar.gz"
      let masterUrl = "https://github.com/" & user & "/" & repo & "/archive/refs/heads/master.tar.gz"
      
      printInfo("Resolving branch for " & user & "/" & repo & "...")
      
      let tmpFile = getTempDir() / "npkg_temp.tar.gz"
      let curlMain = "curl -L -s -o " & quoteShell(tmpFile) & " " & quoteShell(mainUrl)
      discard execShellCmd(curlMain)
      
      let testTar = "tar -tzf " & quoteShell(tmpFile) & " > /dev/null 2>&1"
      
      if execShellCmd(testTar) == 0:
        if fileExists(tmpFile): removeFile(tmpFile)
        downloadAndExtract(mainUrl, packageName)
      else:
        printInfo("'main' branch not found, trying 'master'...")
        let curlMaster = "curl -L -s -o " & quoteShell(tmpFile) & " " & quoteShell(masterUrl)
        discard execShellCmd(curlMaster)
        
        if execShellCmd(testTar) == 0:
          if fileExists(tmpFile): removeFile(tmpFile)
          downloadAndExtract(masterUrl, packageName)
        else:
          printError("Could not find a valid 'main' or 'master' branch for this repository.")
          if fileExists(tmpFile): removeFile(tmpFile)
          return
    else:
      printError("Invalid format. Use 'user/repo' or a direct .tar.gz URL.")
      return
  else:
    printError("Please provide a valid URL or 'user/repo' format.")
    return

# --- KALDIRMA (REMOVE) ---
# --- KALDIRMA (REMOVE) ---
proc removePackage(packageName: string) =
  ensureRoot()
  
  let targetDir = InstallDir / packageName
  let globalBin = "/usr/local/bin" / packageName
  
  var cleaned = false

  # 1. /usr/local/bin altındaki symlink'i veya dosyayı temizle
  if fileExists(globalBin) or symlinkExists(globalBin):
    removeFile(globalBin)
    printInfo("Removed binary symlink: " & globalBin)
    cleaned = true

  # 2. /opt/npkg/ altındaki paket klasörünü temizle
  if dirExists(targetDir):
    removeDir(targetDir)
    printInfo("Removed package directory: " & targetDir)
    cleaned = true
    
  # 3. Registry kaydını güncelle
  var reg = loadRegistry()
  if reg.hasKey(packageName):
    reg.delete(packageName)
    saveRegistry(reg)
    cleaned = true

  if cleaned:
    printSuccess("Successfully removed package: " & packageName)
  else:
    printError("Package not found: " & packageName)
# --- GÜNCELLEME (UPDATE) ---
proc updatePackages() =
  ensureRoot()
  
  let reg = loadRegistry()
  if reg.len == 0:
    printInfo("No installed packages to update.")
    return

  printInfo("Updating installed packages system-wide...")
  for key, val in reg.pairs:
    if val.hasKey("url"):
      let url = val["url"].getStr()
      printInfo("Updating: " & key)
      downloadAndExtract(url, key)
  printSuccess("All packages updated successfully!")

# --- YARDIM / KULLANIM ---
proc printHelp() =
  echo Bold, "npkg (System-Wide) - CLI Package Manager v", Version, Reset
  echo "\nUsage:"
  echo "  sudo npkg add <user/repo | url>  Install a package system-wide"
  echo "  sudo npkg remove <package_name>  Remove a package"
  echo "  npkg search <query>              Search packages (no root required)"
  echo "  sudo npkg update                 Update all installed packages"
  echo "  npkg help                        Show this help message"

# --- MAIN ---
proc main() =
  var 
    command = ""
    target = ""

  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      if command == "":
        command = key.normalize()
      elif target == "":
        target = key
    of cmdLongOption, cmdShortOption:
      discard
    of cmdEnd:
      discard

  case command
  of "add":
    if target == "":
      printError("Please specify a package to add (user/repo or URL).")
    else:
      addPackage(target)
  of "remove":
    if target == "":
      printError("Please specify a package name to remove.")
    else:
      removePackage(target)
  of "search":
    if target == "":
      printError("Please specify a search query.")
    else:
      searchPackages(target)
  of "update":
    updatePackages()
  else:
    printHelp()

when isMainModule:
  main()
