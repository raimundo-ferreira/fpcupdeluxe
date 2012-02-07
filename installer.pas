{ Installer unit for FPCUp
Copyright (C) 2012 Reinier Olislagers

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Library General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at your
option) any later version with the following modification:

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent modules,and
to copy and distribute the resulting executable under terms of your choice,
provided that you also meet, for each linked independent module, the terms
and conditions of the license of that module. An independent module is a
module which is not derived from or based on this library. If you modify
this library, you may extend this exception to your version of the library,
but you are not obligated to do so. If you do not wish to do so, delete this
exception statement from your version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
for more details.

You should have received a copy of the GNU Library General Public License
along with this library; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}
unit installer;

{
Gets/updates/compiles/installs FPC/Lazarus sources
Uses updater unit to get/update the sources.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, updater;

type
  { TInstaller }
  TInstaller = class(TObject)
  private
    FBinUtils: TStringlist; //binutils such as make.exe, as.exe, needed for compilation
    FBootstrapCompilerDirectory: string;
    FBootstrapCompilerFTP: string;
    FCompilerName: string; //Platform specific compiler name (e.g. ppc386.exe for Windows)
    FShortcutName: string; //Name for shortcut/shell script pointing to newly installed Lazarus
    FExecutableExtension: string; //.exe on Windows
    FFPCPlatform: string; //Identification for platform in compiler path (e.g. i386-win32)
    FInstalledCompiler: string; //Path to installed FPC compiler; used to compile Lazarus
    FInstalledCrossCompiler: string; //Path to an optional cross compiler that we installed (also used for Lazarus)
    FInstalledLazarus: string; //Path to installed Lazarus; used in creating shortcuts
    FLazarusPrimaryConfigPath: string;
    FMake: string;
    {$IFDEF WINDOWS}
    FBinutilsDir: string;
    FBinutilsDirNoBackslash: string; //Location of binutils without trailing delimiter
    {$ENDIF}
    //todo: check if we shouldn't rather use FSVNExecutable, extract dir from that.
    FSVNDirectory: string; //Unpack SVN files in this directory. Actual SVN exe may be below this directory.
    FUpdater: TUpdater;
    FExtractor: string; //Location or name of executable used to decompress source arhives
    procedure CreateBinutilsList;
    procedure CreateDesktopShortCut(Target, TargetArguments, ShortcutName: string) ;
    procedure CreateHomeStartLink(Target, TargetArguments, ShortcutName: string);
    function DownloadBinUtils: boolean;
    function DownloadBootstrapCompiler: boolean;
    function DownloadFTP(URL, TargetFile: string): boolean;
    function DownloadHTTP(URL, TargetFile: string): boolean;
    function DownloadSVN: boolean;
    function CheckAndGetNeededExecutables: boolean;
    function FindSVNSubDirs(): boolean;
    function GetBootstrapCompiler: string;
    //Checks for binutils, svn.exe and downloads if needed. Returns true if all prereqs are met.
    function GetFpcDirectory: string;
    function GetFPCUrl: string;
    function GetLazarusDirectory: string;
    function GetLazarusUrl: string;
    function GetMakePath: string;
    function Run(Executable: string; const Params: TStringList): longint;
    function RunOutput(Executable: string; const Params: TStringList; var Output: TStringList): longint;
    function RunOutput(Executable: string; const Params: TStringList; var Output: string): longint;
    procedure SetBootstrapCompilerDirectory(AValue: string);
    procedure SetFPCDirectory(Directory: string);
    procedure SetFPCUrl(AValue: string);
    procedure SetLazarusDirectory(Directory: string);
    procedure SetLazarusUrl(AValue: string);
    procedure SetMakePath(AValue: string);
  public
    property ShortCutName: string read FShortcutName write FShortcutName; //Name of the shortcut to Lazarus. If empty, no shortcut is generated.
    property CompilerName: string read FCompilerName;
    //Full path to FPC compiler that is installed by this program
    property BootstrapCompiler: string read GetBootstrapCompiler;
    //Full path to FPC compiler used to compile the downloaded FPC compiler sources
    property BootstrapCompilerDirectory: string
      read FBootstrapCompilerDirectory write SetBootstrapCompilerDirectory;
    //Directory that has compiler needed to compile compiler sources. If compiler doesn't exist, it will be downloaded
    property BootstrapCompilerFTP: string read FBootstrapCompilerFTP
      write FBootstrapCompilerFTP;
    //Optional; URL from which to download bootstrap FPC compiler if it doesn't exist yet.
    property FPCDirectory: string read GetFPCDirectory write SetFPCDirectory;
    property FPCURL: string read GetFPCUrl write SetFPCUrl; //SVN URL for FPC
    function GetFPC: boolean; //Get/update FPC
    function GetLazarus: boolean; //Get/update Lazarus
    property LazarusDirectory: string read GetLazarusDirectory write SetLazarusDirectory;
    property LazarusPrimaryConfigPath: string
      read FLazarusPrimaryConfigPath write FLazarusPrimaryConfigPath;
    //The directory where the configuration for this Lazarus instance must be stored.
    property LazarusURL: string read GetLazarusUrl write SetLazarusUrl;
    //SVN URL for Lazarus
    property MakePath: string read GetMakePath write SetMakePath;
    //Directory of make executable and other binutils. If it doesn't exist, make and binutils will be downloaded
    constructor Create;
    destructor Destroy; override;
  end;

procedure debugln(Message: string);
//Uses writeln for now, and waits a bit afterwards so output is hopefully not garbled

implementation

uses
  httpsend {for downloading from http},
  ftpsend {for downloading from ftp},
  strutils, process, FileUtil {Requires LCL}, bunzip2
{$IFDEF WINDOWS}
  //Mostly for shortcut code
  ,windows, shlobj {for special folders}, ActiveX, ComObj
{$ENDIF WINDOWS}
{$IFDEF UNIX}
  ,baseunix
{$ENDIF UNIX}
  ,updatelazconfig
  ;

procedure debugln(Message: string);
begin
  {DEBUG conditional symbol is defined using
  Project Options/Other/Custom Options using -dDEBUG
  }
  {$IFDEF DEBUG}
  writeln('Debug: ' + Message);
  sleep(200); //hopefully allow output to be written without interfering with other output
  {$ENDIF DEBUG}
end;

{$IFDEF WINDOWS}
procedure TInstaller.CreateDesktopShortCut(Target, TargetArguments, ShortcutName: string);
var
  IObject: IUnknown;
  ISLink: IShellLink;
  IPFile: IPersistFile;
  PIDL: PItemIDList;
  InFolder: array[0..MAX_PATH] of Char;
  LinkName: WideString;
begin
  { Creates an instance of IShellLink }
  IObject := CreateComObject(CLSID_ShellLink);
  ISLink := IObject as IShellLink;
  IPFile := IObject as IPersistFile;

  ISLink.SetPath(pChar(Target));
  ISLink.SetArguments(pChar(TargetArguments));
  ISLink.SetWorkingDirectory(pChar(ExtractFilePath(Target)));

  { Get the desktop location }
  SHGetSpecialFolderLocation(0, CSIDL_DESKTOPDIRECTORY, PIDL);
  SHGetPathFromIDList(PIDL, InFolder);
  LinkName := InFolder + PathDelim + ShortcutName+'.lnk';

  { Get rid of any existing shortcut first }
  SysUtils.DeleteFile(LinkName);

  { Create the link }
  IPFile.Save(PWChar(LinkName), false);
end;
{$ENDIF WINDOWS}

{$IFDEF UNIX}
procedure TInstaller.CreateDesktopShortCut(Target, TargetArguments, ShortcutName: string);
begin
  debugln('todo: implement createdesktopshortcut.');
end;
{$ENDIF UNIX}

procedure TInstaller.CreateHomeStartLink(Target, TargetArguments,
  ShortcutName: string);
var
  ScriptText: TStringList;
  ScriptFile: string;
begin
  {$IFDEF WINDOWS}
  debugln('todo: write me (CreateHomeStartLink)!');
  {$ENDIF WINDOWS}
  {$IFDEF UNIX}
  ScriptText:=TStringList.Create;
  try
    // No quotes here, either, we're not in a shell, apparently...
    ScriptFile:=ExpandFileNameUTF8('~')+DirectorySeparator+ShortcutName;
    SysUtils.DeleteFile(ScriptFile); //Get rid of any existing remnants
    ScriptText.Add('#!/bin/sh');
    ScriptText.Add('# shortcut to Lazarus trunk, generated by fcpup');
    ScriptText.Add(Target+' '+TargetArguments);
    ScriptText.SaveToFile(ScriptFile);
    FPChmod(ScriptFile, &700); //rwx------
  finally
    ScriptText.Free;
  end;
  {$ENDIF UNIX}
end;

procedure TInstaller.CreateBinutilsList;
// Windows-centric for now; doubt if it
// can be used in Unixy systems anyway
begin
  // We need FExecutableExtension to be defined first.
  FBinUtils:=TStringList.Create;
  FBinUtils.Add('GoRC'+FExecutableExtension);
  FBinUtils.Add('ar'+FExecutableExtension);
  FBinUtils.Add('as'+FExecutableExtension);
  FBinUtils.Add('bin2obj'+FExecutableExtension);
  FBinUtils.Add('cmp'+FExecutableExtension);
  FBinUtils.Add('cp'+FExecutableExtension);
  FBinUtils.Add('cpp.exe');
  FBinUtils.Add('cygiconv-2.dll');
  FBinUtils.Add('cygncurses-8.dll');
  FBinUtils.Add('cygwin1.dll');
  FBinUtils.Add('diff'+FExecutableExtension);
  FBinUtils.Add('dlltool'+FExecutableExtension);
  FBinUtils.Add('fp32.ico');
  FBinUtils.Add('gcc'+FExecutableExtension);
  FBinUtils.Add('gdate'+FExecutableExtension);
  //GDB.exe apparently can also be found here:
  //http://svn.freepascal.org/svn/lazarus/binaries/i386-win32/gdb/bin/
  //for Windows x64:
  //http://svn.freepascal.org/svn/lazarus/binaries/x86_64-win64/gdb/bin/
  FBinUtils.Add('gdb'+FExecutableExtension);
  FBinUtils.Add('gecho'+FExecutableExtension);
  FBinUtils.Add('ginstall'+FExecutableExtension);
  FBinUtils.Add('ginstall.exe.manifest');
  FBinUtils.Add('gmkdir'+FExecutableExtension);
  FBinUtils.Add('grep'+FExecutableExtension);
  FBinUtils.Add('ld'+FExecutableExtension);
  FBinUtils.Add('libexpat-1.dll');
  FBinUtils.Add('make'+FExecutableExtension);
  FBinUtils.Add('mv'+FExecutableExtension);
  FBinUtils.Add('objdump'+FExecutableExtension);
  FBinUtils.Add('patch'+FExecutableExtension);
  FBinUtils.Add('patch.exe.manifest');
  FBinUtils.Add('pwd'+FExecutableExtension);
  FBinUtils.Add('rm'+FExecutableExtension);
  FBinUtils.Add('strip'+FExecutableExtension);
  FBinUtils.Add('unzip'+FExecutableExtension);
  //We might just use gecho for that but that would probably confuse people:
  FBinUtils.Add('upx'+FExecutableExtension);
  FBinUtils.Add('windres'+FExecutableExtension);
  FBinUtils.Add('windres'+FExecutableExtension);
  FBinUtils.Add('zip'+FExecutableExtension);
end;

{ TInstaller }
function TInstaller.DownloadBinUtils: boolean;
// Download binutils. For now, only makes sense on Windows...
const
  {These would be the latest:
  SourceUrl = 'http://svn.freepascal.org/svn/fpcbuild/trunk/install/binw32/';
  These might work but are development, too (might end up in 2.6.2):
  SourceUrl = 'http://svn.freepascal.org/svn/fpcbuild/branches/fixes_2_6/install/binw32/';
  but let's use a stable version:}
  SourceURL = 'http://svn.freepascal.org/svn/fpcbuild/tags/release_2_6_0/install/binw32/';
  //Parent directory of files. Needs trailing backslash.
var
  Counter: integer;
begin
  ForceDirectories(MakePath);
  Result := False;
  //todo: check downloading for linux/osx etc
  for Counter := 0 to FBinUtils.Count - 1 do
  begin
    debugln('Downloading: ' + FBinUtils[Counter] + ' into ' + MakePath);
    try
      DownloadHTTP(SourceUrl + FBinUtils[Counter], MakePath + FBinUtils[Counter]);
    except
      on E: Exception do
      begin
        Result := False;
        debugln('Error downloading binutils: ' + E.Message);
        exit; //out of function.
      end;
    end;
  end;
  Result := True;
end;

function TInstaller.DownloadBootstrapCompiler: boolean;
  // Should be done after we have unzip executable in FMakePath
var
  BootstrapArchive: string;
  Log: string;
  OperationSucceeded: boolean;
  Params: TStringList;
  ArchiveDir: string;
begin
  OperationSucceeded:=true;
  if OperationSucceeded then
  begin
    OperationSucceeded:=ForceDirectories(BootstrapCompilerDirectory);
  end;

  BootstrapArchive := SysUtils.GetTempFileName;
  ArchiveDir := ExtractFilePath(BootstrapArchive);
  if OperationSucceeded then
  begin
    OperationSucceeded:=DownloadFTP(FBootstrapCompilerFTP, BootstrapArchive);
  end;

  if OperationSucceeded then
  begin
    {$IFDEF WINDOWS}
    //Extract zip, overwriting without prompting
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('-o'); //overwrite existing files
      Params.Add('-d'); //Note: apparently we can't call (the FPC supplied) unzip.exe -d with "s
      Params.Add(ArchiveDir);
      Params.Add(BootstrapArchive); // zip/archive file
      if Run(FExtractor, Params) <> 0 then
      begin
        debugln('Error: Received non-zero exit code extracting bootstrap compiler. This will abort further processing.');
        OperationSucceeded := False;
      end
      else
      begin
        OperationSucceeded := True; // Spelling it out can't hurt sometimes
      end;
    finally
      Params.Free;
    end;
    // Move compiler to proper directory
    if OperationSucceeded = True then
    begin
      debugln('Going to rename/move ' + ArchiveDir + CompilerName + ' to ' + BootstrapCompiler);
      renamefile(ArchiveDir + CompilerName, BootstrapCompiler);
    end;
    {$ENDIF WINDOWS}
    {$IFDEF LINUX}
    if OperationSucceeded then
    begin
      //Use internal bunzip2; reminder: external bunzip2 would need -dfq params
      Log:='';
      //Internal Bunzip2 returns false even when it works?!?! So ignore it.
      Bunzip2.Decompress(BootstrapArchive, BootstrapCompiler, Log);
      if Log<>'' then debugln(Log); //output debug output
      Log:=EmptyStr;
    end;
    if OperationSucceeded then
    begin
      //Make executable
      OperationSucceeded:=(fpChmod(BootStrapCompiler, &700)=0); //rwx------
      if OperationSucceeded=false then debugln('todo debug: chmod failed for '+BootstrapCompiler);
    end;
    {$ENDIF LINUX}
    {$IFDEF DARWIN}
    if OperationSucceeded then
    begin
      //Use internal bunzip2; reminder: external bunzip2 would need -dfq params
      Log:='';
      //Internal Bunzip2 returns false even when it works?!?! So ignore it.
      Bunzip2.Decompress(BootstrapArchive, BootstrapCompiler, Log);
      if Log<>'' then debugln(Log); //output debug output
      Log:=EmptyStr;
    end;
    //todo: untar it as well!
    if OperationSucceeded then
    begin
      //Make executable
      OperationSucceeded:=(fpChmod(BootStrapCompiler, &700)=0); //rwx------
    end;
    {$ENDIF DARWIN}
  end;
  if OperationSucceeded = True then
  begin
    SysUtils.DeleteFile(BootstrapArchive);
  end
  else
  begin
    debugln('Error getting/extracting bootstrap compiler. Archive: '+BootstrapArchive);
  end;
  Result := OperationSucceeded;
end;

function TInstaller.DownloadFTP(URL, TargetFile: string): boolean;
const
  FTPPort=21;
  FTPScheme='ftp://'; //URI scheme name for FTP URLs
var
  Host: string;
  Port: integer;
  Source: string;
  FoundPos: integer;
begin
  if LeftStr(URL, length(FTPScheme))=FTPScheme then URL:=Copy(URL, length(FTPScheme)+1, length(URL));
  FoundPos:=pos('/', URL);
  Host:=LeftStr(URL, FoundPos-1);
  Source:=Copy(URL, FoundPos+1, Length(URL));
  //Check for port numbers
  FoundPos:=pos(':', Host);
  Port:=FTPPort;
  if FoundPos>0 then
  begin
    Host:=LeftStr(Host, FoundPos-1);
    Port:=StrToIntDef(Copy(Host, FoundPos+1, Length(Host)),21);
  end;
  Result:=FtpGetFile(Host, IntToStr(Port), Source, TargetFile, 'anonymous', 'fpc@example.com');
end;

function TInstaller.DownloadHTTP(URL, TargetFile: string): boolean;
  // Download file. If ncessary deal with SourceForge redirection, thanks to
  // Ocye: http://lazarus.freepascal.org/index.php/topic,13425.msg70575.html#msg70575
  // todo: check sourceforge redirection code: does it actually work?
const
  SourceForgeProjectPart = '//sourceforge.net/projects/';
  SourceForgeFilesPart = '/files/';
  MaxRetries = 3;
var
  Buffer: TMemoryStream;
  HTTPGetResult: boolean;
  i, j: integer;
  HTTPSender: THTTPSend;
  RetryAttempt: integer;
  SourceForgeProject: string;
begin
  Result := False;
  // Todo: test this functionality
  // Detect SourceForge download
  i := Pos(SourceForgeProjectPart, URL);
  j := Pos(SourceForgeFilesPart, URL);

  // Rewrite URL if needed for Sourceforge download redirection
  if (i > 0) and (j > 0) then
  begin
    SourceForgeProject := Copy(URL, i + Length(SourceForgeProjectPart), j);
    debugln('project is *' + SourceForgeProject + '*');
    try
      HTTPSender := THTTPSend.Create;
      while not Result do
      begin
        HTTPSender.HTTPMethod('GET', URL);
        case HTTPSender.Resultcode of
          301, 302, 307: for i := 0 to HTTPSender.Headers.Count - 1 do
              if (Pos('Location: ', HTTPSender.Headers.Strings[i]) > 0) or
                (Pos('location: ', HTTPSender.Headers.Strings[i]) > 0) then
              begin
                j := Pos('use_mirror=', HTTPSender.Headers.Strings[i]);
                if j > 0 then
                  URL :=
                    'http://' + RightStr(HTTPSender.Headers.Strings[i],
                    length(HTTPSender.Headers.Strings[i]) - j - 10) +
                    '.dl.sourceforge.net/project/' +
                    SourceForgeProject + '/' + 'DiReCtory' + 'FiLeNAMe'
                else
                  URl :=
                    StringReplace(HTTPSender.Headers.Strings[i], 'Location: ', '', []);
                HTTPSender.Clear;//httpsend
                break;
              end;
          100..200: Result := True; //No changes necessary
          500: raise Exception.Create('No internet connection available');
            //Internal Server Error ('+aURL+')');
          else
            raise Exception.Create('Download failed with error code ' +
              IntToStr(HTTPSender.ResultCode) + ' (' + HTTPSender.ResultString + ')');
        end;//case
      end;//while
      debugln('resulting url after sf redir: *' + URL + '*');
    finally
      HTTPSender.Free;
    end;
  end;

  try
    Buffer := TMemoryStream.Create;
    debugln('Going to call httpgetbinary for url: ' + URL);
    RetryAttempt := 1;
    HTTPGetResult := False;
    while ((HTTPGetResult = False) and (RetryAttempt < MaxRetries)) do
    begin
      HTTPGetResult := HttpGetBinary(URL, Buffer);
      //Application.ProcessMessages;
      Sleep(100 * RetryAttempt);
      RetryAttempt := RetryAttempt + 1;
    end;
    if HTTPGetResult = False then
      raise Exception.Create('Cannot load document from remote server');
    Buffer.Position := 0;
    if Buffer.Size = 0 then
      raise Exception.Create('Downloaded document is empty.');
    Buffer.SaveToFile(TargetFile);
    Result := True;
  finally
    FreeAndNil(Buffer);
  end;
end;

function TInstaller.DownloadSVN: boolean;
var
  OperationSucceeded: boolean;
  Params: TStringList;
  ResultCode: longint;
  SVNZip: string;
begin
  // Download SVN in make path. Not required for making FPC/Lazarus, but when downloading FPC/Lazarus from... SVN ;)
  { Alternative 1: sourceforge packaged
  This won't work, we'd get an .msi:
  http://sourceforge.net/projects/win32svn/files/latest/download?source=files
  We don't want msi/Windows installer - this way we can hopefully support Windows 2000, so use:
  http://heanet.dl.sourceforge.net/project/win32svn/1.7.2/svn-win32-1.7.2.zip
  }

  {Alternative 2: use
  http://www.visualsvn.com/files/Apache-Subversion-1.7.2.zip
  with subdirs bin and licenses. No further subdirs
  However, doesn't work on Windows 2K...}
  OperationSucceeded := True;
  ForceDirectories(FSVNDirectory);
  SVNZip := SysUtils.GetTempFileName + '.zip';
  OperationSucceeded := DownloadHTTP(
    'http://heanet.dl.sourceforge.net/project/win32svn/1.7.2/svn-win32-1.7.2.zip'
    , SVNZip);
  if OperationSucceeded then
  begin
    // Extract, overwrite
    // apparently can't specify "s with -d option!??!
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('-o'); //overwrite existing files
      Params.Add('-d'); //Note: apparently we can't call (the FPC supplied) unzip.exe -d with "s
      Params.Add(FSVNDirectory);
      Params.Add(SVNZip); // zip/archive file
      ResultCode:=Run(FExtractor, Params);
      if ResultCode<> 0 then
      begin
        OperationSucceeded := False;
        debugln('resultcode: ' + IntToStr(ResultCode));
      end;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    OperationSucceeded := FindSVNSubDirs;
    if OperationSucceeded then
      SysUtils.deletefile(SVNZip); //Get rid of temp zip if success.
  end;
  Result := OperationSucceeded;
end;

function TInstaller.CheckAndGetNeededExecutables: boolean;
var
  OperationSucceeded: boolean;
  Output: string;
  Params: TStringList;
  ResultCode: longint;
begin
  OperationSucceeded := True;
  // The extractors used depend on the bootstrap compiler URL/file we download
  // todo: adapt extractor based on URL that's being passed (low priority as these will be pretty stable)
  {$IFDEF WINDOWS}
  // Need to do it here so we can pick up make path.
  FExtractor := FBinutilsDir + 'unzip' + FExecutableExtension;
  {$ENDIF WINDOWS}
  {$IFDEF LINUX}
  FExtractor:=''; //We can use internal extractor
  {$ENDIF LINUX}
  {$IFDEF DARWIN}
  FExtractor:='tar'; //We can use internal extractor for bzip2 but need to untar it, too
  {$ENDIF DARIN}

  {$IFDEF WINDOWS}
  if OperationSucceeded then
  begin
    // Check for binutils directory, make and unzip executables.
    // Download if needed; will download unzip - needed for SVN download
    if (DirectoryExists(FBinutilsDir) = False) or (FileExists(FMake) = False) or
      (FileExists(FExtractor) = False) then
    begin
      debugln('Make path ' + FBinutilsDir + ' doesn''t have binutils. Going to download');
      OperationSucceeded := DownloadBinUtils;
    end;
  end;
  {$ENDIF WINDOWS}


  if OperationSucceeded then
  begin
    // Check for proper make executable
    try
      Output := '';
      Params:=TStringList.Create;
      Params.Add('-v');
      try
        ResultCode:=RunOutput(FMake, Params, Output);
      finally
        Params.Free;
      end;

      //todo: verify if we really should ignore errors here
      if Ansipos('GNU Make', Output) = 0 then
        raise Exception.Create('Found make executable but it is not GNU Make.');
    except
      // ignore errors, this is only an extra check
    end;
  end;

  if OperationSucceeded then
  begin
    // Try to look for SVN
    if FUpdater.FindSVNExecutable='' then
    begin
      {$IFDEF Windows}
      // Make sure we have a sensible default.
      // Set it here so multiple calls to CheckExes will not redownload SVN all the time
      if FSVNDirectory='' then FSVNDirectory := 'c:\development\svn\';
      {$ENDIF WINDOWS}
      FindSVNSubDirs; //Find svn in or below FSVNDirectory; will also set Updater's SVN executable
      {$IFDEF Windows}
      // If it still can't be found, download it
      if FUpdater.SVNExecutable='' then
      begin
        debugln('Going to download SVN');
        OperationSucceeded := DownloadSVN;
      end;
      {$ELSE}
      if FUpdater.SVNExecutable='' then
      begin
        debugln('Error: could not find SVN executable. Please make sure it is installed.');
        OperationSucceeded:=false;
      end;
      {$ENDIF}
    end;
  end;

  if OperationSucceeded then
  begin
    // Check for valid unzip/gunzip executable
    if FExtractor<>EmptyStr then
    begin
      try
        Output := '';
        // See unzip.h for return codes.
        Params:=TStringList.Create;
        try
          // Possibly redundant as we now use internal bunzip2 code, but can't hurt
          if AnsiPos('unzip', lowercase(FExtractor))=1 then Params.Add('-v');
          if AnsiPos('bzip2', lowercase(FExtractor))=1 then Params.Add('--version');
          if AnsiPos('bunzip2', lowercase(FExtractor))=1 then Params.Add('--version');
          if AnsiPos('gzip', lowercase(FExtractor))=1 then Params.Add('--version');
          if AnsiPos('gunzip', lowercase(FExtractor))=1 then Params.Add('--version');
          if AnsiPos('tar', lowercase(FExtractor))=1 then Params.Add('--version');
          ResultCode:=RunOutput(FExtractor, Params, Output);
        finally
          Params.Free;
        end;

        if ResultCode=0 then
        begin
          debugln('Found valid extractor: ' + FExtractor);
          OperationSucceeded := true;
        end
        else
        begin
          //invalid unzip/gunzip/whatever
          debugln('Error: could not find valid extractor: ' + FExtractor + ' (result code was: '+IntToStr(ResultCode)+')');
          OperationSucceeded:=false;
        end;
      except
        OperationSucceeded := False;
      end;
    end;
  end;


  if OperationSucceeded then
  begin
    // Check for proper FPC bootstrap compiler
    debugln('Checking for FPC bootstrap compiler...');
    try
      Output := '';
      Params:=TStringList.Create;
      try
        // Show help without waiting:
        Params.Add('-h');
        ResultCode:=RunOutput(BootstrapCompiler, Params, Output);
      finally
        Params.Free;
      end;

      if ResultCode=0 then
      begin
        if Ansipos('Free Pascal Compiler', Output) = 0 then
        begin
          OperationSucceeded := False;
          debugln('Found FPC executable but it is not a Free Pascal compiler. Going to overwrite it.');
        end
        else
        begin
          //valid FPC compiler
          debugln('Found valid FPC bootstrap compiler.');
          OperationSucceeded:=true;
        end;
      end
      else
      begin
        //Error running bootstrapcompiler
        debugln('Error trying to test run bootstrap compiler '+BootstrapCompiler+'. Received output: '+Output+'; resultcode: '+IntToStr(ResultCode));
        OperationSucceeded:=false;
      end;
    except
      on E: Exception do
      begin
        debugln('Exception trying to test run bootstrap compiler '+BootstrapCompiler+'. Received output: '+Output);
        debugln(E.ClassName+'/'+E.Message);
        OperationSucceeded := False;
      end;
    end;
    // Still within bootstrap compiler test...
    if OperationSucceeded=false then
    begin
      debugln('Bootstrap compiler not found or not a proper FPC compiler; downloading.');
      OperationSucceeded := DownloadBootstrapCompiler;
    end;
  end;
  Result := OperationSucceeded;
end;

function TInstaller.FindSVNSubDirs(): boolean;
// Looks through SVN directory and sets updater's SVNExecutable
var
  SVNFiles: TStringList;
  OperationSucceeded: boolean;
begin
  //SVNFiles:=TStringList.Create; //No, Findallfiles does that for you!?!?
  SVNFiles := FindAllFiles(FSVNDirectory, 'svn' + FExecutableExtension, True);
  try
    if SVNFiles.Count > 0 then
    begin
      // Just get first result.
      FUpdater.SVNExecutable := SVNFiles.Strings[0];
      OperationSucceeded := True;
    end
    else
    begin
      debugln('Could not find svn executable in or under ' + FSVNDirectory);
      OperationSucceeded := False;
    end;
  finally
    SVNFiles.Free;
  end;
  Result := OperationSucceeded;
end;

function TInstaller.GetBootstrapCompiler: string;
begin
  Result := BootstrapCompilerDirectory + CompilerName;
end;

function Tinstaller.GetFpcDirectory: string;
begin
  Result := FUpdater.FPCDirectory;
end;

function TInstaller.GetFPCUrl: string;
begin
  Result := FUpdater.FPCURL;
end;

function Tinstaller.GetLazarusDirectory: string;
begin
  Result := FUpdater.LazarusDirectory;
end;

function TInstaller.GetLazarusUrl: string;
begin
  Result := FUpdater.LazarusURL;
end;


function TInstaller.GetMakePath: string;
begin
  {$IFDEF WINDOWS}
  Result := FBinutilsDir;
  {$ELSE}
  Result := ''; //dummy value, done for compatibility
  {$ENDIF WINDOWS}
end;

function TInstaller.Run(Executable: string; const Params: TStringList): longint;
{ Runs executable without showing output, unless:
1. something went wrong (result code<>0) and
2. DEBUG is set
}
var
  OutputStringList: TStringList;
begin
  debugln('Calling:');
  debugln(Executable + ' ' +AnsiReplaceStr(Params.Text, LineEnding, ' '));
  OutputStringList := TStringList.Create;
  try
    Result:=RunOutput(Executable, Params, OutputStringList);
    if result<>0 then
    begin
      debugln('Command returned non-zero ExitStatus: '+IntToStr(result)+'. Output:');
      debugln(OutputStringList.Text);
    end;
  finally
    OutputStringList.Free;
  end;
end;

function TInstaller.RunOutput(Executable: string; const Params: TStringList;
  var Output: TStringList): longint;
var
  SpawnedProcess: TProcess;
  OutputStream: TMemoryStream;

  function ReadOutput: boolean;
    // returns true if output was actually read
  const
    BufSize = 4096;
  var
    Buffer: array[0..BufSize - 1] of byte;
    ReadBytes: integer;
  begin
    Result := False;
    while SpawnedProcess.Output.NumBytesAvailable > 0 do
    begin
      ReadBytes := SpawnedProcess.Output.Read(Buffer, BufSize);
      OutputStream.Write(Buffer, ReadBytes);
      Result := True;
    end;
  end;

begin
  Result := 255; //Preset to failure
  OutputStream := TMemoryStream.Create;
  SpawnedProcess := TProcess.Create(nil);
  try
    try
      SpawnedProcess.Executable:=Executable;
      SpawnedProcess.Parameters:=Params;
      SpawnedProcess.Options := [poUsePipes, poStderrToOutPut];
      SpawnedProcess.ShowWindow := swoHIDE;
      SpawnedProcess.Execute;
      while SpawnedProcess.Running do
      begin
        if not ReadOutput then
          Sleep(100);
      end;
      ReadOutput;
      OutputStream.Position := 0;
      Output.LoadFromStream(OutputStream);
      Result := SpawnedProcess.ExitStatus;
    except
      on E: Exception do
      begin
        //todo: check file not found handling. We don't want to do an explicit file exists
        //as this complicates with paths, current dirs, .exe extensions etc.
        //Something went wrong. We need to pass on what and markt this as a failure
        debugln('Exception calling '+Executable);
        debugln('Details: '+E.ClassName+'/'+E.Message);
        Result:=254; //fairly random but still an error, and distinct from earlier code
      end;
    end;
  finally
    OutputStream.Free;
    SpawnedProcess.Free;
  end;
end;

function TInstaller.RunOutput(Executable: string; const Params: TStringList; var Output: string): longint;
var
  OutputStringList: TStringList;
begin
  OutputStringList := TStringList.Create;
  try
    Result:=RunOutput(Executable, Params, OutputStringList);
    Output := OutputStringList.Text;
  finally
    OutputStringList.Free;
  end;
end;

procedure TInstaller.SetBootstrapCompilerDirectory(AValue: string);
begin
  FBootstrapCompilerDirectory:=IncludeTrailingPathDelimiter(ExpandFileName(AValue));
end;

procedure Tinstaller.SetFPCDirectory(Directory: string);
begin
  FUpdater.FPCDirectory := IncludeTrailingPathDelimiter(ExpandFileName(Directory));
end;

procedure TInstaller.SetFPCUrl(AValue: string);
begin
  FUpdater.FPCURL := AValue;
end;

procedure Tinstaller.SetLazarusDirectory(Directory: string);
begin
  FUpdater.LazarusDirectory := IncludeTrailingPathDelimiter(ExpandFileName(Directory));
end;

procedure TInstaller.SetLazarusUrl(AValue: string);
begin
  FUpdater.LazarusURL := AValue;
end;


procedure TInstaller.SetMakePath(AValue: string);
begin
  {$IFDEF WINDOWS}
  // Make sure there's a trailing delimiter
  FBinutilsDir:=IncludeTrailingPathDelimiter(AValue);
  FBinutilsDirNoBackslash:=ExcludeTrailingPathDelimiter(FBinutilsDir); //We need a stripped version for crossbindir
  FMake:=FBinutilsDir+'make'+FExecutableExtension;
  {$ELSE}
  FMake:='make'; //assume in path
  {$ENDIF WINDOWS}
end;


function Tinstaller.GetFPC: boolean;
var
  BinPath: string; //Path where installed compiler ends up
  Executable: string;
  FileCounter:integer;
  FPCCfg: string;
  OperationSucceeded: boolean;
  Params: TstringList;
begin
  //Make sure we have the proper tools:
  OperationSucceeded:=CheckAndGetNeededExecutables;

  debugln('Checking out/updating FPC sources...');
  if OperationSucceeded then OperationSucceeded:=FUpdater.UpdateFPC;

  if OperationSucceeded then
  begin
    // Make clean using bootstrap compiler
    // Note no error on failure, might be recoverable
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC=' + BootstrapCompiler+'');
      {$IFDEF WINDOWS}
      Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils. NOTE: CROSSBINDIR REQUIRES path NOT to end with trailing delimiter!
      {$ENDIF WINDOWS}
      //Alternative to CROSSBINDIR would be OPT=-FD+FBinutilsDirNoBackslash
      Params.Add('--directory='+ FPCDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('clean');
      debugln('Running make clean for fpc:');
      Run(Executable, params);
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Make all using bootstrap compiler
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC=' + BootstrapCompiler+'');
      {$IFDEF WINDOWS}
      Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils
      {$ENDIF WINDOWS}
      Params.Add('--directory='+ FPCDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('all');
      debugln('Running make for FPC:');
      if Run(Executable, params) <> 0 then
        OperationSucceeded := False;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Install using newly compiled compiler
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC=' + BootstrapCompiler+'');
      {$IFDEF WINDOWS}
      Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils
      {$ENDIF WINDOWS}
      Params.Add('--directory='+ FPCDirectory+'');
      Params.Add('INSTALL_PREFIX='+FPCDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('install');
      debugln('Running make install for FPC:');
      if Run(Executable, Params) <> 0 then
        OperationSucceeded := False;
    finally
      Params.Free;
    end;
  end;

  // Let everyone know of our shiny new compiler:
  if OperationSucceeded then
  begin
    // This differs between Windows and Linux.
    {$IFDEF WINDOWS}
    // This will give something like ppc386.exe. We use this in case
    // we need to pass PP=bla when running make.
    // We mangle this later when dealing with Lazarus config, as we require
    // fpc.exe there.
    FInstalledCompiler := FPCDirectory + 'bin' +
      DirectorySeparator + FFPCPlatform + DirectorySeparator + CompilerName;
    {$ENDIF WINDOWS}
    {$IFDEF UNIX}
    FInstalledCompiler := FPCDirectory + 'bin' +DirectorySeparator+'fpc';
    {$ENDIF UNIX}
  end
  else
  begin
    FInstalledCompiler:='////\\\Error trying to compile FPC\|!';
  end;

  {$IFDEF WINDOWS}
  if OperationSucceeded then
  begin
    //Copy over binutils to new compiler bin directory
    try
      for FileCounter:=0 to FBinUtils.Count-1 do
      begin
        FileUtil.CopyFile(FBinutilsDir+FBinUtils[FileCounter], ExtractFilePath(FInstalledCompiler)+FBinUtils[FileCounter]);
      end;
      // Also, we can change the make/binutils path to our new environment
      // Will modify fmake as well.
      MakePath:=ExtractFilePath(FInstalledCompiler);
    except
      on E: Exception do
      begin
        debugln('Error copying binutils: '+E.Message);
        OperationSucceeded:=false;
      end;
    end;
  end;
  {$ENDIF WINDOWS}

  {$IFDEF WINDOWS}
  if OperationSucceeded then
  begin
    // Make crosscompiler using new compiler- todo: check out what cross compilers we can install on Linux/OSX
    // Note: consider this as an optional item, so don't fail the function if this breaks.
    Executable := FMake;
    debugln('Running Make all (crosscompiler):');
    Params:=TStringList.Create;
    try
      //Don't call parameters with quotes
      Params.Add('FPC='+FInstalledCompiler+'');
      //Should not be needed as we already copied binutils to fpc compiler dir
      //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils; TODO: perhaps replace with 64 bit version?
      Params.Add('--directory='+ FPCDirectory+'');
      Params.Add('INSTALL_PREFIX='+FPCDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('OS_TARGET=win64');
      Params.Add('CPU_TARGET=x86_64');
      Params.Add('all');
      if Run(Executable, Params) = 0 then
      begin
        // Install crosscompiler using new compiler - todo: only for Windows!?!?
        // make all and make crossinstall perhaps equivalent to
        // make all install CROSSCOMPILE=1??? todo: find out
        Executable := FMake;
        debugln('Running Make crossinstall:');
        // Params already assigned
        Params.Clear;
        Params.Add('FPC='+FInstalledCompiler+'');
        //Should not be needed as we already copied binutils to fpc compiler dir
        //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils; TODO: perhaps replace with 64 bit version?
        Params.Add('--directory='+ FPCDirectory+'');
        Params.Add('INSTALL_PREFIX='+FPCDirectory+'');
        Params.Add('UPXPROG=echo'); //Don't use UPX
        Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
        Params.Add('OS_TARGET=win64');
        Params.Add('CPU_TARGET=x86_64');
        Params.Add('crossinstall');
        // Note: consider this as an optional item, so don't fail the function if this breaks.
        if Run(Executable, Params)=0 then
        begin
          // Let everyone know of our shiny new crosscompiler:
          FInstalledCrossCompiler := FPCDirectory + DirectorySeparator + 'bin' +
            DirectorySeparator + FFPCPlatform + DirectorySeparator + 'ppcrossx64.exe';
        end
        else
        begin
          debugln('Problem compiling/installing crosscompiler. Continuing regardless.');
        end;
      end;
    finally
      Params.Free;
    end;
  end;
  {$ENDIF WINDOWS}

  //todo: after fpcmkcfg create a config file for fpkpkg or something
  if OperationSucceeded then
  begin
    // Create fpc.cfg if needed
    BinPath := ExtractFilePath(FInstalledCompiler);
    FPCCfg := BinPath + 'fpc.cfg';
    if FileExists(FPCCfg) = False then
    begin
      Executable := BinPath + 'fpcmkcfg';
      Params:=TStringList.Create;
      try
        Params.Add('-d');
        Params.Add('basepath='+FPCDirectory+'');
        Params.Add('-o');
        Params.Add('' + FPCCfg + '');
        debugln('Debug: Running fpcmkcfg: ');
        if Run(Executable, Params) <> 0 then
          OperationSucceeded := False;
      finally
        Params.Free;
      end;
    end
    else
    begin
      debugln('fpc.cfg already exists; leaving it alone.');
    end;
  end;
  Result := OperationSucceeded;
end;

function Tinstaller.GetLazarus: boolean;
// Note: getlazarus depends on properly installed FPC
// Properly installed in this case means: the way
// GetFPC would install it ;)
// Assumed: binutils in fpc dir or in path
var
  Executable: string;
  LazarusConfig: TUpdateLazConfig;
  OperationSucceeded: boolean;
  Params: TStringList;
begin
  //Make sure we have the proper tools.
  OperationSucceeded := CheckAndGetNeededExecutables;


  // If we haven't installed FPC, this won't be set
  // todo: fix FPC for linux/other platforms
  if FInstalledCompiler = '' then
  begin
    //Assume we've got a working compiler. This will link through to the
    //platform-specific compiler:
    FInstalledCompiler := FPCDirectory + DirectorySeparator + 'bin' +
      DirectorySeparator + FFPCPlatform + DirectorySeparator + CompilerName;
  end;

  // Download Lazarus source:
  if OperationSucceeded = True then
  begin
    debugln('Checking out/updating Lazarus sources...');
    OperationSucceeded := FUpdater.UpdateLazarus;
  end;

  // Make sure primary config path exists
  if DirectoryExists(LazarusPrimaryConfigPath) = False then
  begin
    OperationSucceeded:=ForceDirectories(LazarusPrimaryConfigPath);
    debugln('Created Lazarus primary config directory: '+LazarusPrimaryConfigPath);
  end;

  if OperationSucceeded then
  begin
    // Make clean; failure here might be recoverable, so no fiddling with OperationSucceeded
    // Note: you apparently can't pass FPC in the FPC= statement, you need to pass a PPC executable.
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC='+FInstalledCompiler+'');
      //Should not be needed as we already copied binutils to fpc compiler dir
      //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils
      Params.Add('--directory='+LazarusDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('clean');
      debugln('Lazarus: running make clean:');
      Run(Executable, Params);
    finally
      Params.Free;
    end;
  end;

  {$IFDEF WINDOWS}
  //todo: find out what crosscompilers we can install on linux/osx
  if OperationSucceeded then
  begin
    // LCL 64 bit crosscompiler.
    if FInstalledCrossCompiler<>'' then
    begin
      Executable := FMake;
      Params:=TStringList.Create;
      try
        //Don't call params with quotes
        Params.Add('FPC='+FInstalledCrossCompiler+'');
        //Should not be needed as we already copied binutils to fpc compiler dir
        //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils; TODO: perhaps replace with 64 bit version?
        Params.Add('--directory='+LazarusDirectory+'');
        Params.Add('UPXPROG=echo'); //Don't use UPX
        Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
        Params.Add('LCL_PLATFORM=win32');
        Params.Add('OS_TARGET=win64');
        Params.Add('CPU_TARGET=x86_64');
        Params.Add('lcl');
        debugln('Lazarus: running make lcl crosscompiler:');
        // Note: consider this optional; don't fail the function if this fails.
        if Run(Executable, Params)<> 0 then debugln('Problem compiling 64 bit LCL; continuing regardless.');
      finally
        Params.Free;
      end;
    end;
  end;
  {$ENDIF WINDOWS}

  if OperationSucceeded then
  begin
    // Make all (should include lcl & ide)
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC='+FInstalledCompiler+'');
      //Should not be needed as we already copied binutils to fpc compiler dir
      //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils
      Params.Add('--directory='+LazarusDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('all');
      debugln('Lazarus: running make all:');
      if (Run(Executable, Params)) <> 0 then
      begin
        OperationSucceeded := False;
        FInstalledLazarus:= '//*\\error//\\'; //todo: check if this really is an invalid filename. it should be.
      end
      else
      begin
        FInstalledLazarus:=LazarusDirectory+'lazarus'+FExecutableExtension;
      end;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Set up a minimal config so we can use LazBuild
    LazarusConfig:=TUpdateLazConfig.Create(LazarusPrimaryConfigPath);
    try
      try
        // FInstalledCompiler will be something like c:\bla\ppc386.exe, e.g.
        // the platform specific compiler. In order to be able to cross compile
        // we'd rather use fpc
        LazarusConfig.CompilerFilename:=ExtractFilePath(FInstalledCompiler)+'fpc'+FExecutableExtension;
        LazarusConfig.LazarusDirectory:=LazarusDirectory;
        {$IFDEF WINDOWS}
        LazarusConfig.DebuggerFilename:=FBinutilsDir+'gdb'+FExecutableExtension;
        LazarusConfig.MakeFilename:=FBinutilsDir+'make'+FExecutableExtension;
        {$ENDIF WINDOWS}
        {$IFDEF UNIX}
        //todo: fix this for more variants?!?
        LazarusConfig.DebuggerFilename:='gdb'+FExecutableExtension; //assume in path
        LazarusConfig.MakeFilename:='make'+FExecutableExtension; //assume in path
        {$ENDIF UNIX}
        // Source dir in stock Lazarus on windows is something like
        // $(LazarusDir)fpc\$(FPCVer)\source\
        LazarusConfig.FPCSourceDirectory:=FPCDirectory;
      except
        on E: Exception do
        begin
          OperationSucceeded:=false;
          debugln('Error setting Lazarus config: '+E.ClassName+'/'+E.Message);
        end;
      end;
    finally
      LazarusConfig.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Make bigide: ide with additional packages as specified by user (in primary config path?)
    Executable := FMake;
    Params:=TStringList.Create;
    try
      //Don't call params with quotes
      Params.Add('FPC='+FInstalledCompiler+'');
      //Should not be needed as we already copied binutils to fpc compiler dir
      //Params.Add('CROSSBINDIR='+FBinutilsDirNoBackslash+''); //Show make where to find the binutils
      Params.Add('--directory='+LazarusDirectory+'');
      Params.Add('UPXPROG=echo'); //Don't use UPX
      Params.Add('COPYTREE=echo'); //fix for examples in Win svn, see build FAQ
      Params.Add('bigide');
      debugln('Lazarus: running make bigide:');
      if (Run(Executable, Params)) <> 0 then
        OperationSucceeded := False;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Build data desktop, nice example of building with lazbuild
    Executable := LazarusDirectory + DirectorySeparator + 'lazbuild';
    Params:=TStringList.Create;
    try
      //Do NOT pass quotes in params
      Params.Add('--primary-config-path='+FLazarusPrimaryConfigPath+'');
      Params.Add(''+LazarusDirectory+
        'tools'+DirectorySeparator+
        'lazdatadesktop'+DirectorySeparator+
        'lazdatadesktop.lpr');
      debugln('Lazarus: compiling data desktop:');
      if (Run(Executable, Params)) <> 0 then
        OperationSucceeded := False;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // Build Lazarus Doceditor
    Executable := LazarusDirectory + DirectorySeparator + 'lazbuild';
    Params:=TStringList.Create;
    try
      //Do NOT pass quotes in params
      Params.Add('--primary-config-path='+FLazarusPrimaryConfigPath+'');
      Params.Add(''+LazarusDirectory+
        'doceditor'+DirectorySeparator+
        'lazde.lpr');
      debugln('Lazarus: compiling doc editor:');
      if (Run(Executable, Params)) <> 0 then
        OperationSucceeded := False;
    finally
      Params.Free;
    end;
  end;

  if OperationSucceeded then
  begin
    // For Windows, a desktop shortcut. For Unixy systems, a script in ~
    {$IFDEF WINDOWS}
    if ShortCutName<>EmptyStr then
    begin
      debugln('Lazarus: creating desktop shortcut:');
      try
        //Create shortcut; we don't care very much if it fails=>don't mess with OperationSucceeded
        //todo: perhaps check for existing shortcut
        //DO pass quotes here (it's not TProcess.Params)
        CreateDesktopShortCut(FInstalledLazarus,'--pcp="'+FLazarusPrimaryConfigPath+'"',ShortCutName);
      finally
        //Ignore problems creating shortcut
      end;
    end;
    {$ENDIF WINDOWS}
    {$IFDEF UNIX}
    if ShortCutName<>EmptyStr then
    begin
      debugln('Lazarus: creating shortcut in your home directory');
      try
        //Create shortcut; we don't care very much if it fails=>don't mess with OperationSucceeded
        //DO pass quotes here (it's not TProcess.Params)
        CreateHomeStartLink(FInstalledLazarus,'--pcp="'+FLazarusPrimaryConfigPath+'"',ShortcutName);
      finally
        //Ignore problems creating shortcut
      end;
    end;
    {$ENDIF UNIX}
  end;

  Result := OperationSucceeded;
end;

constructor Tinstaller.Create;
const
  {$IFDEF WINDOWS}
  DefaultPCPSubdir='lazarusdevsettings'; //Include the name lazarus for easy searching Caution: shouldn't be the same name as Lazarus dir itself.
  {$ENDIF WINDOWS}
  {$IFDEF UNIX}
  DefaultPCPSubdir='.lazarusdevsettings'; //Include the name lazarus for easy searching Caution: shouldn't be the same name as Lazarus dir itself.
  {$ENDIF UNIX}
var
  AppDataPath: array[0..MaxPathLen] of char; //Allocate memory
begin
  // We'll set the bootstrap compiler to a file in the temp dir.
  // This won't exist so the CheckAndGetNeededExecutables code will download it for us.
  // User can specify an existing compiler later on, if she wants to.
  FBootstrapCompilerDirectory := SysUtils.GetTempDir;

  //Bootstrap compiler:
  //BootstrapURL='ftp://ftp.freepascal.org/pub/fpc/dist/2.4.2/bootstrap/i386-win32-ppc386.zip';
  {$IFDEF Windows}
  FBootstrapCompilerFTP :=
    'ftp.freepascal.org/pub/fpc/dist/2.6.0/bootstrap/i386-win32-ppc386.zip';
  FCompilername := 'ppc386.exe';
  FFPCPlatform:='i386-win32';
  {$ENDIF Windows}
  {$IFDEF Linux}
  FBootstrapCompilerFTP :=
    'ftp.freepascal.org/pub/fpc/dist/2.6.0/bootstrap/i386-linux-ppc386.bz2';
  //todo: check if this is the right one - 32vs64 bit!?!?
  {todo: Linux x86:
  FCompilername := 'ppc386';
  FDesktopShortcutName:='Lazarus (dev version)';
  FFPCPlatform:='i386-linux';
  }
  FBootstrapCompilerFTP :=
  'ftp.freepascal.org/pub/fpc/dist/2.6.0/bootstrap/x86_64-linux-ppcx64.bz2';
  FCompilername := 'x86_64-linux-ppcx64';
  FFPCPlatform:='x86_64';
  {$ENDIF Linux}
  {$IFDEF Darwin}
  FBootstrapCompilerFTP:=
    'ftp.freepascal.org/pub/fpc/dist/2.6.0/bootstrap/universal-darwin-ppcuniversal.tar.bz2';
  FCompilername := 'ppcuniversal';
  //check this:
  FFPCPlatform:='x64-OSX';
  {$ENDIF Darwin}

  {$IFDEF WINDOWS}
  FExecutableExtension := '.exe';
  {$ELSE}
  FExecutableExtension := '';
  {$ENDIF WINDOWS}
  // Binutils needed for compilation
  CreateBinutilsList;

  FInstalledCompiler := '';
  FLazarusPrimaryConfigPath := '';
  FSVNDirectory := '';
  FUpdater := TUpdater.Create;
  FExtractor := '';
  //Directory where Lazarus installation config will end up (primary config path)
  {$IFDEF Windows}
  // Somewhere in local appdata special folder
  AppDataPath := '';
  SHGetSpecialFolderPath(0, AppDataPath, CSIDL_LOCAL_APPDATA, False);
  LazarusPrimaryConfigPath := AppDataPath + DirectorySeparator + DefaultPCPSubdir;
  {$ELSE}
  LazarusPrimaryConfigPath:=GetAppConfigDir(false)+DefaultPCPSubdir;
  {$ENDIF}
  SetMakePath('');
end;

destructor Tinstaller.Destroy;
begin
  FUpdater.Free;
  FBinUtils.Free;
  inherited Destroy;
end;

end.

