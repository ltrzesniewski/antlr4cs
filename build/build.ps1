param (
	[switch]$Debug,
	[string]$VisualStudioVersion = "15.0",
	[switch]$NoClean,
	[string]$Verbosity = "minimal",
	[string]$Logger,
	[string]$Java6Home,
	[string]$MavenHome,
	[string]$MavenRepo,
	[switch]$SkipMaven,
	[switch]$SkipKeyCheck,
	[switch]$GenerateTests,
	[switch]$NoValidate
)

# build the solution
$SolutionPath = "..\Runtime\CSharp\Antlr4.sln"

# make sure the script was run from the expected path
if (!(Test-Path $SolutionPath)) {
	$host.UI.WriteErrorLine("The script was run from an invalid working directory.")
	exit 1
}

. .\version.ps1

If ($Debug) {
	$BuildConfig = 'Debug'
} Else {
	$BuildConfig = 'Release'
}

If ($AntlrVersion.Contains('-')) {
	$KeyConfiguration = 'Dev'
} Else {
	$KeyConfiguration = 'Final'
}

If ($NoClean) {
	$Target = 'build'
} Else {
	$Target = 'rebuild'
}

If (-not $MavenHome) {
	$MavenHome = $env:M2_HOME
}

$Java6RegKey = 'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\1.6'
$Java6RegValue = 'JavaHome'
If (-not $Java6Home -and (Test-Path $Java6RegKey)) {
	$JavaHomeKey = Get-Item -LiteralPath $Java6RegKey
	If ($JavaHomeKey.GetValue($Java6RegValue, $null) -ne $null) {
		$JavaHomeProperty = Get-ItemProperty $Java6RegKey $Java6RegValue
		$Java6Home = $JavaHomeProperty.$Java6RegValue
	}
}

# Build the Java library using Maven
If (-not $SkipMaven) {
	$OriginalPath = $PWD

	cd '..\tool'
	$MavenPath = "$MavenHome\bin\mvn.cmd"
	If (-not (Test-Path $MavenPath)) {
		$MavenPath = "$MavenHome\bin\mvn.bat"
	}

	If (-not (Test-Path $MavenPath)) {
		$host.ui.WriteErrorLine("Couldn't locate Maven binary: $MavenPath")
		cd $OriginalPath
		exit 1
	}

	If (-not $Java6Home -or -not (Test-Path $Java6Home)) {
		$host.ui.WriteErrorLine("Couldn't locate Java 6 installation: $Java6Home")
		cd $OriginalPath
		exit 1
	}

	If ($GenerateTests) {
		$SkipTestsArg = 'false'
	} Else {
		$SkipTestsArg = 'true'
	}

	If ($MavenRepo) {
		$MavenRepoArg = "-Dmaven.repo.local=`"$MavenRepo`""
	}

	$MavenGoal = 'package'
	&$MavenPath '-B' $MavenRepoArg "-DskipTests=$SkipTestsArg" '--errors' '-e' '-Dgpg.useagent=true' "-Djava6.home=$Java6Home" '-Psonatype-oss-release' $MavenGoal
	if (-not $?) {
		$host.ui.WriteErrorLine('Maven build of the C# Target custom Tool failed, aborting!')
		cd $OriginalPath
		Exit $LASTEXITCODE
	}

	cd $OriginalPath
}

# this is configured here for path checking, but also in the .props and .targets files
[xml]$pom = Get-Content "..\tool\pom.xml"
$CSharpToolVersionNodeInfo = Select-Xml "/mvn:project/mvn:version" -Namespace @{mvn='http://maven.apache.org/POM/4.0.0'} $pom
$CSharpToolVersion = $CSharpToolVersionNodeInfo.Node.InnerText.trim()

$nuget = '..\runtime\CSharp\.nuget\NuGet.exe'
If (-not (Test-Path $nuget)) {
	If (-not (Test-Path '..\runtime\CSharp\.nuget')) {
		mkdir '..\runtime\CSharp\.nuget'
	}

	$nugetSource = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
	Invoke-WebRequest $nugetSource -OutFile $nuget
	If (-not $?) {
		$host.ui.WriteErrorLine('Unable to download NuGet executable, aborting!')
		exit $LASTEXITCODE
	}
}

# build the main project
$visualStudio = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VS7')."$VisualStudioVersion"
$msbuild = "$visualStudio\MSBuild\$VisualStudioVersion\Bin\MSBuild.exe"
If (-not (Test-Path $msbuild)) {
	$host.UI.WriteErrorLine("Couldn't find MSBuild.exe")
	exit 1
}

If ($Logger) {
	$LoggerArgument = "/logger:$Logger"
}

&$nuget 'restore' $SolutionPath -Project2ProjectTimeOut 1200
&$msbuild '/nologo' '/m' '/nr:false' "/t:$Target" $LoggerArgument "/verbosity:$Verbosity" "/p:Configuration=$BuildConfig" "/p:VisualStudioVersion=$VisualStudioVersion" "/p:KeyConfiguration=$KeyConfiguration" $SolutionPath
if (-not $?) {
	$host.ui.WriteErrorLine('Build failed, aborting!')
	Exit $LASTEXITCODE
}

if (-not (Test-Path 'nuget')) {
	mkdir "nuget"
}

$JarPath = "..\tool\target\antlr4-csharp-$CSharpToolVersion-complete.jar"
if (!(Test-Path $JarPath)) {
	$host.ui.WriteErrorLine("Couldn't locate the complete jar used for building C# parsers: $JarPath")
	exit 1
}

# By default, do not create a NuGet package unless the expected strong name key files were used
if (-not $SkipKeyCheck) {
	. .\keys.ps1

	foreach ($pair in $Keys.GetEnumerator()) {
		$assembly = Resolve-FullPath -Path "..\runtime\CSharp\Antlr4.Runtime\bin\$BuildConfig\$($pair.Key)\Antlr4.Runtime.dll"

		# Run the actual check in a separate process or the current process will keep the assembly file locked
		powershell -Command ".\check-key.ps1 -Assembly '$assembly' -ExpectedKey '$($pair.Value)' -Build '$($pair.Key)'"
		if (-not $?) {
			Exit $LASTEXITCODE
		}
	}
}

$packages = @(
	'Antlr4.CodeGenerator'
	'Antlr4')

ForEach ($package in $packages) {
	If (-not (Test-Path ".\$package.nuspec")) {
		$host.ui.WriteErrorLine("Couldn't locate NuGet package specification: $package")
		exit 1
	}

	&$nuget 'pack' ".\$package.nuspec" '-OutputDirectory' 'nuget' '-Prop' "Configuration=$BuildConfig" '-Version' "$AntlrVersion" '-Prop' "M2_REPO=$M2_REPO" '-Prop' "CSharpToolVersion=$CSharpToolVersion" '-Symbols'
	if (-not $?) {
		Exit $LASTEXITCODE
	}
}

# Validate code generation using the Java code generator
If (-not $NoValidate) {
	git 'clean' '-dxf' 'DotnetValidationJavaCodegen'
	dotnet 'run' '--project' '.\DotnetValidationJavaCodegen\DotnetValidation.csproj' '--framework' 'netcoreapp1.1'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	git 'clean' '-dxf' 'DotnetValidationJavaCodegen'
	dotnet 'run' '--project' '.\DotnetValidationJavaCodegen\DotnetValidation.csproj' '--framework' 'netcoreapp2.1'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	git 'clean' '-dxf' 'DotnetValidationJavaCodegen'
	&$nuget 'restore' 'DotnetValidationJavaCodegen'
	&$msbuild '/nologo' '/m' '/nr:false' '/t:Rebuild' $LoggerArgument "/verbosity:$Verbosity" "/p:Configuration=$BuildConfig" '.\DotnetValidationJavaCodegen\DotnetValidation.sln'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\net20\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\net30\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\net35\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\net40\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\portable40-net40+sl5+win8+wp8+wpa81\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidationJavaCodegen\bin\$BuildConfig\net45\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}
}

# Validate code generation using the C# code generator
If (-not $NoValidate) {
	git 'clean' '-dxf' 'DotnetValidation'
	dotnet 'run' '--project' '.\DotnetValidation\DotnetValidation.csproj' '--framework' 'netcoreapp1.1'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	git 'clean' '-dxf' 'DotnetValidation'
	dotnet 'run' '--project' '.\DotnetValidation\DotnetValidation.csproj' '--framework' 'netcoreapp2.1'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	git 'clean' '-dxf' 'DotnetValidation'
	&$nuget 'restore' 'DotnetValidation'
	&$msbuild '/nologo' '/m' '/nr:false' '/t:Rebuild' $LoggerArgument "/verbosity:$Verbosity" "/p:Configuration=$BuildConfig" '.\DotnetValidation\DotnetValidation.sln'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\net20\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\net30\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\net35\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\net40\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\portable40-net40+sl5+win8+wp8+wpa81\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	".\DotnetValidation\bin\$BuildConfig\net45\DotnetValidation.exe"
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}
}

# Validate code generation using the C# code generator (single target framework)
If (-not $NoValidate) {
	git 'clean' '-dxf' 'DotnetValidationSingleTarget'
	dotnet 'run' '--project' '.\DotnetValidationSingleTarget\DotnetValidation.csproj' '--framework' 'netcoreapp1.1'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}

	git 'clean' '-dxf' 'DotnetValidationSingleTarget'
	&$nuget 'restore' 'DotnetValidationSingleTarget'
	&$msbuild '/nologo' '/m' '/nr:false' '/t:Rebuild' $LoggerArgument "/verbosity:$Verbosity" "/p:Configuration=$BuildConfig" '.\DotnetValidationSingleTarget\DotnetValidation.sln'
	if (-not $?) {
		$host.ui.WriteErrorLine('Build failed, aborting!')
		Exit $LASTEXITCODE
	}
}
