# Windows scene fixtures run inside the Java process using the published classifier.
function Get-GodotFixtureLaunch {
    param([string[]]$EngineArguments, [string]$WorkingDirectory = (Get-Location).Path)
    $workspace = Split-Path $PSScriptRoot -Parent
    $jdkPath = if ($env:GODOT_JFX_JDK) { $env:GODOT_JFX_JDK } else { $env:JAVA_HOME }
    $distribution = Join-Path $workspace 'artifacts/godot-library'
    $version = (Get-Content -LiteralPath "$distribution/version.txt" -Raw).Trim()
    $jars = foreach ($module in 'base','graphics','controls','fxml','media','swing') {
        $classifier = if ($module -in 'graphics','media') { '-win' } else { '' }
        (Get-Item -LiteralPath "$distribution/repository/org/godotjfx/javafx-$module/$version/javafx-$module-$version$classifier.jar").FullName
    }
    $classes = Join-Path $workspace 'artifacts/reference'
    $source = Get-Item -LiteralPath "$workspace/tests/reference/GodotSceneFixture.java"
    $compiled = Get-Item -LiteralPath "$classes/GodotSceneFixture.class" -ErrorAction SilentlyContinue
    if (!$compiled -or $compiled.LastWriteTimeUtc -lt $source.LastWriteTimeUtc) {
        New-Item -ItemType Directory -Force $classes | Out-Null
        & "$jdkPath/bin/javac.exe" -cp ($jars -join ';') -d $classes $source.FullName
        if ($LASTEXITCODE) { throw 'Godot scene launcher compilation failed' }
    }
    $vfx = Join-Path $workspace 'artifacts/vfx'
    $classpath = @($jars) + @($classes, "$vfx/classes/java/main", "$vfx/classes/java/test", "$vfx/resources/main", "$vfx/resources/test", "$vfx/dependencies/*")
    $index = [Array]::IndexOf($EngineArguments, '--path')
    if ($index -ge 0 -and (Resolve-Path -LiteralPath $EngineArguments[$index+1]).Path -eq "$workspace\tests\godot") {
        $project = & python "$PSScriptRoot/prepare-godot-fixture.py"
        if ($LASTEXITCODE) { throw 'Could not prepare the Godot test project' }
        $EngineArguments[$index+1] = Join-Path "$workspace/artifacts" $project
    } elseif ($index -lt 0) {
        $EngineArguments = @('--path', $WorkingDirectory) + $EngineArguments
    }
    [pscustomobject]@{ Java = "$jdkPath/bin/java.exe"; Arguments = @('--enable-native-access=ALL-UNNAMED','-cp',($classpath -join ';'),'GodotSceneFixture') + $EngineArguments }
}

function Invoke-GodotFixture {
    $launch = Get-GodotFixtureLaunch $args
    $prefix = $launch.Arguments
    & $launch.Java @prefix
}

function Start-GodotFixture {
    param([string[]]$ArgumentList, [string]$WorkingDirectory, [string]$Log, [string]$ErrorLog)
    $launch = Get-GodotFixtureLaunch $ArgumentList $WorkingDirectory
    $quoted = foreach ($argument in $launch.Arguments) { '"' + $argument + '"' }
    Start-Process -FilePath $launch.Java -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $Log -RedirectStandardError $ErrorLog -PassThru
}
