# ==============================================================================
#  Authors:
#    Patrick Lehmann
#
# ==============================================================================
#  Copyright (C) 2017-2021 Patrick Lehmann - Boetzingen, Germany
#  Copyright (C) 2015-2016 Patrick Lehmann - Dresden, Germany
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <gnu.org/licenses>.
# ==============================================================================

# .SYNOPSIS
# Script to compile the simulation libraries from Xilinx Vivado for GHDL on Windows.
#
# .DESCRIPTION
# This CmdLet:
#   (1) creates a subdirectory in the current working directory
#   (2) compiles all Xilinx Vivado simulation libraries and packages
#       - unisim (incl. secureip)
#       - unimacro
#
[CmdletBinding()]
param(
	# Show the embedded help page(s)
	[switch]$Help =             $false,

	# Compile all libraries and packages.
	[switch]$All =              $false,

	# Compile the Xilinx simulation library.
	[switch]$Unisim =           $false,

	# Compile the Xilinx macro library.
	[switch]$Unimacro =         $false,

	# Compile the Xilinx secureip library.
	[switch]$SecureIP =         $false,

	# Clean up directory before analyzing.
	[switch]$Clean =            $false,

	# Set VHDL Standard to '93.
	[switch]$VHDL93 =           $false,
	# Set VHDL Standard to '08.
	[switch]$VHDL2008 =         $false,

	# Skip warning messages. (Show errors only.)
	[switch]$SuppressWarnings = $false,
	# Halt on errors.
	[switch]$HaltOnError =      $false,

	# Set vendor library source directory.
	[string]$Source =           "",
	# Set output directory name.
	[string]$Output =           "",
	# Set GHDL binary directory.
	[string]$GHDL =             ""
)

# ---------------------------------------------
# save working directory
$WorkingDir =     Get-Location

# set default values
$EnableDebug =    [bool]$PSCmdlet.MyInvocation.BoundParameters["Debug"]
$EnableVerbose =  [bool]$PSCmdlet.MyInvocation.BoundParameters["Verbose"] -or $EnableDebug

# load modules from GHDL's 'vendors' library directory
$EnableVerbose -and  (Write-Host "Loading modules..." -ForegroundColor Gray  ) | Out-Null
$EnableDebug -and    (Write-Host "  Import-Module $PSScriptRoot\config.psm1 -Verbose:`$$false -Debug:`$$false -ArgumentList `"XilinxVivado`"" -ForegroundColor DarkGray  ) | Out-Null
Import-Module $PSScriptRoot\config.psm1 -Verbose:$false -ArgumentList "XilinxVivado"
$EnableDebug -and    (Write-Host "  Import-Module $PSScriptRoot\shared.psm1 -Verbose:`$$false -Debug:`$$false -ArgumentList @(`"Xilinx Vivado`", `"$WorkingDir`")" -ForegroundColor DarkGray  ) | Out-Null
Import-Module $PSScriptRoot\shared.psm1 -Verbose:$false -ArgumentList @("Xilinx Vivado", "$WorkingDir")

# Display help if no command was selected
$Help = $Help -or (-not ($All -or $Unisim -or $Simprim -or $Unimacro))

if ($Help)
{	Get-Help $MYINVOCATION.MyCommand.Path -Detailed
	Exit-CompileScript
}
if ($All)
{	$Unisim =   $true
	$Simprim =  $true
	$Unimacro = $true
	$SecureIP = $true
}

function Get-XilinxVivadoDirectory
{	if (Test-Path env:XILINX_VIVADO)
	{	return $env:XILINX_VIVADO + "\" + (Get-VendorToolSourceDirectory)    }
	else
	{	$EnvSourceDir = ""
		foreach ($Drive in Get-PSDrive -PSProvider 'FileSystem')
		{	$Path = $Drive.Name + ":\" + "Xilinx\Vivado"
			if (Test-Path $Path -PathType Container)
			{	foreach ($Major in 2021..2014)
				{	foreach ($Minor in 4..1)
					{	$Dir = $Path + "\" + $Major + "." + $Minor
						if (Test-Path $Dir -PathType Container)
						{	$EnvSourceDir = $Dir + "\" + (Get-VendorToolSourceDirectory)
							return $EnvSourceDir
						}
					}
				}
			}
		}
	}
}

$SourceDirectory =      Get-SourceDirectory $Source (Get-XilinxVivadoDirectory)
$DestinationDirectory = Get-DestinationDirectory $Output
$GHDLBinary =           Get-GHDLBinary $GHDL

# create "Altera" directory and change to it
New-DestinationDirectory $DestinationDirectory
cd $DestinationDirectory

if ($VHDL2008)
{	Write-Host "Not all Xilinx primitives are VHDL-2008 compatible! Setting HaltOnError to FALSE." -ForegroundColor Red
	$HaltOnError =      $false
}
$VHDLVersion,$VHDLStandard,$VHDLFlavor = Get-VHDLVariables -VHDL93:$VHDL93 -VHDL2008:$VHDL2008

# define global GHDL Options
$Analyze_Parameters = @(
	"--std=$VHDLStandard",
	"-fexplicit",
	"-frelaxed-rules",
	"--mb-comments",
	"-Wbinding"
)
if (-not $EnableDebug)
{	$Analyze_Parameters += @(
		"-Wno-hide"
	)
}
if (-not ($EnableVerbose -or $EnableDebug))
{ $Analyze_Parameters += @(
		"-Wno-library",
		"-Wno-others",
		"-Wno-static"
	)
}
$Analyze_Parameters += @(
	"--ieee=$VHDLFlavor",
	"--no-vital-checks",
	"-P$DestinationDirectory"
)

# extract data from configuration
# $SourceDir =      $InstallationDirectory["AlteraQuartus"] + "\quartus\eda\sim_lib"

$StopCompiling =  $false
$ErrorCount =     0


# Cleanup directories
# ==============================================================================
if ($Clean)
{	Write-Host "[ERROR]: '-Clean' is not implemented!" -ForegroundColor Red
	Exit-CompileScript -1

	Write-Host "Cleaning up vendor directory ..." -ForegroundColor Yellow
	rm *.cf
}


# Library UNISIM
# ==============================================================================
# compile unisim packages
if ((-not $StopCompiling) -and $Unisim)
{	$Library = "unisim"
	$Files = @(
		"unisims\unisim_VPKG.vhd",
		"unisims\unisim_VCOMP.vhd",
		"unisims\retarget_VCOMP.vhd",
		"unisims\unisim_retarget_VCOMP.vhd"
	)
	$SourceFiles = $Files | % { "$SourceDirectory\$_" }

	$ErrorCount += Start-PackageCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# compile unisim primitives
if ((-not $StopCompiling) -and $Unisim)
{	$Library = "unisim"
	$SourceFiles = dir "$SourceDirectory\unisims\primitive\*.vhd*"

	$ErrorCount += Start-PrimitiveCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# compile unisim retarget primitives
if ((-not $StopCompiling) -and $Unisim)
{	$Library = "unisim"
	$SourceFiles = dir "$SourceDirectory\unisims\retarget\*.vhd*"

	$ErrorCount += Start-PrimitiveCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# compile unisim secureip primitives
if ((-not $StopCompiling) -and $Unisim -and $SecureIP)
{	$Library = "secureip"
	$SourceFiles = dir "$SourceDirectory\unisims\secureip\*.vhd*"

	$ErrorCount += Start-PrimitiveCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# Library UNIMACRO
# ==============================================================================
# compile unimacro packages
if ((-not $StopCompiling) -and $Unimacro)
{	$Library = "unimacro"
	$Files = @(
		"unimacro\unimacro_VCOMP.vhd"
	)
	$SourceFiles = $Files | % { "$SourceDirectory\$_" }

	$ErrorCount += Start-PackageCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# compile unimacro macros
if ((-not $StopCompiling) -and $Unimacro)
{	$Library = "unimacro"
	$SourceFiles = dir "$SourceDirectory\unimacro\*_MACRO.vhd*"

	$ErrorCount += Start-PrimitiveCompilation $GHDLBinary $Analyze_Parameters $DestinationDirectory $Library $VHDLVersion $SourceFiles $SuppressWarnings $HaltOnError -Verbose:$EnableVerbose -Debug:$EnableDebug
	$StopCompiling = $HaltOnError -and ($ErrorCount -ne 0)
}

# Library UNIFAST
# ==============================================================================
# TODO:

Write-Host "--------------------------------------------------------------------------------"
Write-Host "Compiling Xilinx Vivado libraries " -NoNewline
if ($ErrorCount -gt 0)
{	Write-Host "[FAILED]" -ForegroundColor Red        }
else
{	Write-Host "[SUCCESSFUL]" -ForegroundColor Green  }

Exit-CompileScript
