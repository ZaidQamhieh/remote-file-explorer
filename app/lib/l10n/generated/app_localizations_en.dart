// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Remote File Explorer';

  @override
  String get browseButton => 'Browse';

  @override
  String get searchButton => 'Search';

  @override
  String get moreTooltip => 'More';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get appSettingsTooltip => 'App settings';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get retryButton => 'Retry';

  @override
  String get okButton => 'OK';

  @override
  String get saveButton => 'Save';

  @override
  String get closeButton => 'Close';

  @override
  String get addButton => 'Add';

  @override
  String get createButton => 'Create';

  @override
  String get applyButton => 'Apply';

  @override
  String get resetButton => 'Reset';

  @override
  String get updateButton => 'Update';

  @override
  String get dismissButton => 'Dismiss';

  @override
  String get undoButton => 'Undo';

  @override
  String get continueButton => 'Continue';

  @override
  String get replaceButton => 'Replace';

  @override
  String get discardButton => 'Discard';

  @override
  String get pairButton => 'Pair';

  @override
  String get onlineStatus => 'Online';

  @override
  String get offlineStatus => 'Offline';

  @override
  String get checkingStatus => 'Checking…';

  @override
  String get networkLan => 'LAN';

  @override
  String get networkTailscale => 'Tailscale';

  @override
  String hostSubtitleVersionNetwork(String version, String network) {
    return 'v$version · $network';
  }

  @override
  String statusCheckedRelative(String relative) {
    return 'Checked $relative';
  }

  @override
  String statusOfflineLastSeen(String relative) {
    return 'Offline · last seen $relative';
  }

  @override
  String get relativeJustNow => 'just now';

  @override
  String relativeSecondsAgo(int count) {
    return '${count}s ago';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String relativeHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String relativeDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get couldNotReachComputer => 'Could not reach this computer.';

  @override
  String get forgetComputerTitle => 'Forget this computer?';

  @override
  String forgetComputerConfirm(String hostLabel) {
    return 'Remove \"$hostLabel\"? You can re-add it later.';
  }

  @override
  String get forgetButton => 'Forget';

  @override
  String get forgetComputerMenuItem => 'Forget this computer';

  @override
  String get storageMenuItem => 'Storage';

  @override
  String get transfersMenuItem => 'Transfers';

  @override
  String get diagnosticsMenuItem => 'Diagnostics';

  @override
  String get settingsMenuItem => 'Settings';

  @override
  String nMoreDrives(int count) {
    return '+$count more';
  }

  @override
  String get addComputerButton => 'Add computer';

  @override
  String get scanQrCodeButton => 'Scan QR code';

  @override
  String get emptyStatePairTitle => 'Pair your first PC';

  @override
  String get emptyStatePairBody =>
      'Scan the pairing QR code shown by the desktop agent to connect this phone over your network or Tailscale.';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get connectionDiagnosticsTitle => 'Connection Diagnostics';

  @override
  String get retestButton => 'Re-test';

  @override
  String get probeTimedOut => 'Timed out';

  @override
  String get probeError => 'Error';

  @override
  String probeLatencyMs(int ms) {
    return '${ms}ms';
  }

  @override
  String hostStorageTitle(String hostLabel) {
    return '$hostLabel · Storage';
  }

  @override
  String get allDrives => 'All drives';

  @override
  String couldNotLoadStorage(String error) {
    return 'Could not load storage: $error';
  }

  @override
  String freeOfTotal(String free, String total) {
    return '$free free of $total';
  }

  @override
  String freeOfTotalDrives(String free, String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count drives',
      one: '1 drive',
    );
    return '$free free of $total · $_temp0';
  }

  @override
  String get searchHint => 'Search files and folders…';

  @override
  String get clearTooltip => 'Clear';

  @override
  String get searchFiltersTooltip => 'Search filters';

  @override
  String activeFilterCount(int count) {
    return '$count';
  }

  @override
  String get globPattern => 'Glob pattern';

  @override
  String get clearAllButton => 'Clear all';

  @override
  String get removeTooltip => 'Remove';

  @override
  String get fileSize => 'File size';

  @override
  String get searchScope => 'Search scope';

  @override
  String get fromHere => 'From here';

  @override
  String get everywhere => 'Everywhere';

  @override
  String get includeHiddenItems => 'Include hidden items';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String noResultsFor(String query) {
    return 'No results for \"$query\".';
  }

  @override
  String get typeToSearch => 'Type to search for files and folders by name.';

  @override
  String showingFirstNResults(int limit) {
    return 'Showing first $limit results — refine your search.';
  }

  @override
  String get searchTimedOut => 'Search timed out — showing partial results.';

  @override
  String searchingIn(String path) {
    return 'Searching in: $path';
  }

  @override
  String get searchingEverywhere => 'Searching everywhere';

  @override
  String get searchTooltip => 'Search';

  @override
  String get clearSelectionTooltip => 'Clear selection';

  @override
  String get batchRenameTooltip => 'Batch rename';

  @override
  String get invertSelectionTooltip => 'Invert selection';

  @override
  String get selectAllTooltip => 'Select all';

  @override
  String get deselectAllTooltip => 'Deselect all';

  @override
  String nSelected(int count) {
    return '$count selected';
  }

  @override
  String get uploadFileTooltip => 'Upload file';

  @override
  String get newButton => 'New';

  @override
  String get favoriteFolderTooltip => 'Favorite this folder';

  @override
  String get removeFavoriteTooltip => 'Remove favorite';

  @override
  String get viewOptionsTitle => 'View options';

  @override
  String get layoutLabel => 'Layout';

  @override
  String get listLabel => 'List';

  @override
  String get gridLabel => 'Grid';

  @override
  String get densityLabel => 'Density';

  @override
  String get comfortableLabel => 'Comfortable';

  @override
  String get compactLabel => 'Compact';

  @override
  String get sortByLabel => 'Sort by';

  @override
  String get showHiddenItems => 'Show hidden items';

  @override
  String nHiddenByVisibility(int count) {
    return '$count hidden by file visibility settings';
  }

  @override
  String get newFolderButton => 'New folder';

  @override
  String get newFileButton => 'New file';

  @override
  String get nameHint => 'Name';

  @override
  String createdName(String name) {
    return 'Created $name';
  }

  @override
  String createFailed(String name, String error) {
    return 'Couldn\'t create $name: $error';
  }

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get noFavoritesYet =>
      'No favorites yet. Open a folder and tap the star to bookmark it.';

  @override
  String get cancelTooltip => 'Cancel';

  @override
  String get nameConflictTitle => 'Name conflict';

  @override
  String nameConflictBody(int collidingCount, int totalCount, String dest) {
    String _temp0 = intl.Intl.pluralLogic(
      totalCount,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$collidingCount of $totalCount $_temp0 already exist in $dest.';
  }

  @override
  String get skipTheseButton => 'Skip these';

  @override
  String get keepBothButton => 'Keep both';

  @override
  String get overwriteButton => 'Overwrite';

  @override
  String get previewButton => 'Preview';

  @override
  String get downloadButton => 'Download';

  @override
  String get extractHereButton => 'Extract here';

  @override
  String get renameButton => 'Rename';

  @override
  String get duplicateButton => 'Duplicate';

  @override
  String get deleteButton => 'Delete';

  @override
  String get newNameLabel => 'New name';

  @override
  String get deleteTitle => 'Delete?';

  @override
  String get deleteForeverButton => 'Delete forever';

  @override
  String get moveToTrashButton => 'Move to Trash';

  @override
  String get favoriteButton => 'Favorite';

  @override
  String get unfavoriteButton => 'Unfavorite';

  @override
  String get yesLabel => 'Yes';

  @override
  String copiedPath(String path) {
    return 'Copied \"$path\"';
  }

  @override
  String get copyPathAction => 'Copy path';

  @override
  String get pastePathAction => 'Paste path';

  @override
  String get clipboardEmptyMessage => 'Clipboard is empty';

  @override
  String removedFavorite(String name) {
    return 'Removed \"$name\" from favorites';
  }

  @override
  String addedFavorite(String name) {
    return 'Added \"$name\" to favorites';
  }

  @override
  String downloadingFile(String name) {
    return 'Downloading $name…';
  }

  @override
  String renamedTo(String newName) {
    return 'Renamed to $newName';
  }

  @override
  String renameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String duplicatedFile(String name) {
    return 'Duplicated \"$name\"';
  }

  @override
  String duplicateFailed(String error) {
    return 'Duplicate failed: $error';
  }

  @override
  String extractedFile(String name) {
    return 'Extracted \"$name\"';
  }

  @override
  String extractFailed(String error) {
    return 'Extract failed: $error';
  }

  @override
  String moveToTrashConfirm(String name) {
    return 'Move \"$name\" to Trash? You can restore it later.';
  }

  @override
  String deletedName(String name) {
    return 'Deleted $name';
  }

  @override
  String movedToTrashName(String name) {
    return 'Moved $name to Trash';
  }

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get folderDetailsTooltip => 'Folder details';

  @override
  String get trashTitle => 'Trash';

  @override
  String get emptyTrashTooltip => 'Empty trash';

  @override
  String get deleteForeverTitle => 'Delete forever?';

  @override
  String get emptyTrashTitle => 'Empty trash?';

  @override
  String get restoreButton => 'Restore';

  @override
  String get recentTitle => 'Recent';

  @override
  String get recentIsEmpty => 'No recent files';

  @override
  String get recentEmptySubtitle => 'Files you edit will show up here.';

  @override
  String get recentTimedOut => 'Scan timed out — showing partial results.';

  @override
  String get patternLabel => 'Pattern';

  @override
  String get findAndReplaceLabel => 'Find & replace';

  @override
  String get baseNameLabel => 'Base name';

  @override
  String get startNumberLabel => 'Start number';

  @override
  String get findLabel => 'Find';

  @override
  String get replaceWithLabel => 'Replace with';

  @override
  String renameNItemsTitle(int count) {
    return 'Rename $count items';
  }

  @override
  String renameNItems(int count) {
    return 'Rename $count';
  }

  @override
  String get baseNameHelperText =>
      'Place the number with the n token; else it\'\'s appended.';

  @override
  String andNMore(int count) {
    return '… and $count more';
  }

  @override
  String batchSuccessNItems(String verb, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return '$verb $count $_temp0';
  }

  @override
  String batchResultWithErrors(String verb, int errorCount) {
    return '$verb with $errorCount error(s)';
  }

  @override
  String get cutButton => 'Cut';

  @override
  String get copyButton => 'Copy';

  @override
  String get compressButton => 'Compress';

  @override
  String moveNItemsToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return 'Move $count $_temp0 to Trash?';
  }

  @override
  String canRestoreFromTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'them',
      one: 'it',
    );
    return 'You can restore $_temp0 from Trash.';
  }

  @override
  String compressedTo(String name) {
    return 'Compressed to $name';
  }

  @override
  String compressFailed(String error) {
    return 'Compress failed: $error';
  }

  @override
  String queuedNDownloads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'downloads',
      one: 'download',
    );
    return 'Queued $count $_temp0';
  }

  @override
  String get deletedLabel => 'Deleted';

  @override
  String get movedToTrashLabel => 'Moved to Trash';

  @override
  String clipboardCopiedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 copied — open a folder and tap Paste';
  }

  @override
  String clipboardCutHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 cut — open a folder and tap Paste';
  }

  @override
  String pasteNItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return 'Paste $count $_temp0';
  }

  @override
  String get movedLabel => 'Moved';

  @override
  String get copiedLabel => 'Copied';

  @override
  String get moveLabel => 'Move';

  @override
  String get copyLabel => 'Copy';

  @override
  String operationFailed(String operation, String error) {
    return '$operation failed: $error';
  }

  @override
  String alreadyExistsSkipped(String name) {
    return '$name already exists — skipped';
  }

  @override
  String uploadingFile(String name) {
    return 'Uploading $name…';
  }

  @override
  String nHidden(int count) {
    return '$count hidden';
  }

  @override
  String get hideLabel => 'Hide';

  @override
  String get showLabel => 'Show';

  @override
  String itemExistsInFolder(String name, String folder) {
    return '$name already exists in $folder';
  }

  @override
  String couldNotCheckFolder(String folder, String error) {
    return 'Could not check $folder for existing items: $error';
  }

  @override
  String movedFile(String name) {
    return 'Moved $name';
  }

  @override
  String moveFailed(String error) {
    return 'Move failed: $error';
  }

  @override
  String nothingToPaste(String folder, String operation) {
    return '$folder — nothing to $operation';
  }

  @override
  String pathLabel(String label) {
    return '$label · ';
  }

  @override
  String get showHiddenFoldersTooltip => 'Show hidden folders';

  @override
  String get addComputerTitle => 'Add computer';

  @override
  String get scanQrTab => 'Scan QR';

  @override
  String get manualTab => 'Manual';

  @override
  String get loginTab => 'Log in';

  @override
  String get agentAddressLabel => 'Agent address';

  @override
  String get agentAddressHint => '192.168.1.10:8765';

  @override
  String get pairingCodeLabel => 'Pairing code';

  @override
  String get pairingCodeHint => '123456';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Log in';

  @override
  String loginFailed(String error) {
    return 'Login failed: $error';
  }

  @override
  String get loginHint =>
      'No account yet? Run \"rfe-agent adduser <username>\" on the PC once, then log in from any device.';

  @override
  String get registerTab => 'Register';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get passwordMismatch => 'Passwords don\'t match';

  @override
  String get registerButton => 'Create account';

  @override
  String registerFailed(String error) {
    return 'Registration failed: $error';
  }

  @override
  String get registerHint =>
      'Creates your account and pairs this device in one step. Run \"rfe-agent pair\" on the PC first to get a code — the same one-time code used for Scan QR / Manual.';

  @override
  String get requiredLabel => 'Required';

  @override
  String pairedWith(String name) {
    return 'Paired with $name';
  }

  @override
  String fingerprintMismatch(String error) {
    return 'Fingerprint mismatch: $error';
  }

  @override
  String pairingFailed(String error) {
    return 'Pairing failed: $error';
  }

  @override
  String get photoBackupTitle => 'Photo backup';

  @override
  String get enablePhotoBackup => 'Enable photo backup';

  @override
  String get photoBackupSubtitle => 'One-way: copies new photos to your PC';

  @override
  String get backUpTo => 'Back up to';

  @override
  String get deviceNicknameLabel => 'This phone\'s nickname';

  @override
  String get deviceNicknameHint => 'e.g. Zaid\'s Phone';

  @override
  String get onlyOnWifi => 'Only on Wi-Fi';

  @override
  String get onlyWhileCharging => 'Only while charging';

  @override
  String photosBackedUp(int count) {
    return '$count photo(s) backed up';
  }

  @override
  String get albumsToBackUp => 'Albums to back up';

  @override
  String get allPhotos => 'All photos';

  @override
  String get selectAlbums => 'Select albums';

  @override
  String albumsSelected(int count) {
    return '$count album(s) selected';
  }

  @override
  String albumPhotoCount(int count) {
    return '$count photo(s)';
  }

  @override
  String get enableBackupFirst => 'Enable photo backup first';

  @override
  String get shareTooltip => 'Share';

  @override
  String get shareLinkButton => 'Share link';

  @override
  String get shareLinkSheetTitle => 'Share link';

  @override
  String shareLinkExpiresIn(String time) {
    return 'Expires in $time';
  }

  @override
  String get shareLinkExpired => 'Link expired';

  @override
  String get shareLinkRevokeButton => 'Revoke';

  @override
  String get shareLinkRevoked => 'Share link revoked';

  @override
  String shareLinkFailed(String error) {
    return 'Share link failed: $error';
  }

  @override
  String get saveToDeviceTooltip => 'Save to device';

  @override
  String get showInFolderTooltip => 'Show in folder';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get fileChangedOnDisk => 'File changed on disk';

  @override
  String get reloadButton => 'Reload';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get unsavedChangesMessage =>
      'You have unsaved changes that will be lost.';

  @override
  String get keepEditingButton => 'Keep editing';

  @override
  String get saveTooltip => 'Save';

  @override
  String savedFile(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String couldNotSaveFile(String error) {
    return 'Could not save this file.\n$error';
  }

  @override
  String couldNotReloadFile(String error) {
    return 'Could not reload this file.\n$error';
  }

  @override
  String get editTooltip => 'Edit';

  @override
  String get hideLineNumbers => 'Hide line numbers';

  @override
  String get appSettingsTitle => 'App settings';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get useWallpaperColors => 'Use wallpaper colors';

  @override
  String get displaySection => 'Display';

  @override
  String get updatesSection => 'Updates';

  @override
  String get photoBackupSection => 'Photo backup';

  @override
  String get copyPhonePhotos => 'Copy phone photos to a PC';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get agentSection => 'Agent';

  @override
  String get agentNameLabel => 'Agent name';

  @override
  String get accessSection => 'Access';

  @override
  String get readOnlyMode => 'Read-only mode';

  @override
  String get enableShareLinks => 'Enable share links';

  @override
  String get shareLinksEnabledHint => 'Files can be shared via one-time links';

  @override
  String get shareLinksDisabledHint => 'Share links are turned off';

  @override
  String get allowedFoldersSection => 'Allowed folders';

  @override
  String get addFolderTooltip => 'Add folder';

  @override
  String get removeFolderTooltip => 'Remove folder';

  @override
  String get pairedDevicesSection => 'Paired devices';

  @override
  String get aboutSection => 'About';

  @override
  String get pcNameLabel => 'PC name';

  @override
  String get disconnectButton => 'Disconnect';

  @override
  String get disconnectDeviceTitle => 'Disconnect this device?';

  @override
  String get addAllowedFolder => 'Add allowed folder';

  @override
  String get allowedFolderHint => '/home/me/Documents';

  @override
  String get renameAgentTitle => 'Rename agent';

  @override
  String get hideDotfiles => 'Hide dotfiles';

  @override
  String get hideDotfilesSubtitle =>
      'Hide files and folders starting with \".\"';

  @override
  String get customLabel => 'Custom';

  @override
  String dotExtension(String ext) {
    return '.$ext';
  }

  @override
  String get fileVisibilitySection => 'File visibility';

  @override
  String get fileVisibilityDeviceSection => 'File visibility (this device)';

  @override
  String get overrideForDevice => 'Override for this device';

  @override
  String get addExtensionHint => 'Add extension (e.g. tmp)';

  @override
  String get addExtensionTooltip => 'Add extension';

  @override
  String get displayDeviceSection => 'Display (this device)';

  @override
  String get resetToAppDefaults => 'Reset to app defaults';

  @override
  String get displayFollowsDefaults =>
      'These follow your app defaults unless you override them here.';

  @override
  String get sortLabel => 'Sort';

  @override
  String get backupRestoreSection => 'Backup & restore';

  @override
  String get exportConfig => 'Export config';

  @override
  String get importConfig => 'Import config';

  @override
  String get importConfigSubtitle => 'Restore from a previously exported file';

  @override
  String get exportConfigTitle => 'Export config';

  @override
  String get importConfigTitle => 'Import config';

  @override
  String get replaceCurrentConfig => 'Replace current config?';

  @override
  String get passphraseLabel => 'Passphrase';

  @override
  String get confirmPassphraseLabel => 'Confirm passphrase';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String updatedToVersion(String version) {
    return 'Updated to v$version ✓';
  }

  @override
  String upToDate(String version) {
    return 'Up to date (v$version)';
  }

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get couldNotOpenInstaller => 'Could not open the installer.';

  @override
  String updatingToVersion(String version) {
    return 'Updating to v$version';
  }

  @override
  String get downloadingStatus => 'Downloading…';

  @override
  String downloadingProgress(
    String percent,
    String received,
    String totalSize,
  ) {
    return 'Downloading $percent%  ·  $received / $totalSize';
  }

  @override
  String get openingInstaller => 'Opening installer…';

  @override
  String get somethingWentWrong => 'Something went wrong.';

  @override
  String updateAvailable(String version) {
    return 'Update available · v$version';
  }

  @override
  String fmtMB(String value) {
    return '$value MB';
  }

  @override
  String fmtKB(String value) {
    return '$value KB';
  }

  @override
  String fmtBytes(String value) {
    return '$value B';
  }

  @override
  String get clearCompletedButton => 'Clear completed';

  @override
  String get noTransfers => 'No transfers';

  @override
  String get queuedStatus => 'Queued';

  @override
  String get pauseTooltip => 'Pause';

  @override
  String get resumeTooltip => 'Resume';

  @override
  String removedTransfer(String name) {
    return 'Removed $name';
  }

  @override
  String transferProgress(String transferred, String total) {
    return '$transferred / $total';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String get uploadedStatus => 'Uploaded';

  @override
  String get downloadedStatus => 'Downloaded';

  @override
  String savedToLocation(String location) {
    return 'Saved to $location';
  }

  @override
  String sha256Prefix(String hash) {
    return 'SHA-256 $hash…';
  }

  @override
  String transferringFile(String name) {
    return 'Transferring $name';
  }

  @override
  String transferringFileAndMore(String name, int count) {
    return 'Transferring $name (+$count more)';
  }

  @override
  String get loadingImage => 'Loading image…';

  @override
  String couldNotLoadImage(String error) {
    return 'Could not load image.\n$error';
  }

  @override
  String get decodingImage => 'Decoding image…';

  @override
  String couldNotDecodeImage(String error) {
    return 'Could not decode this image.\n$error';
  }

  @override
  String get loadingPdf => 'Loading PDF…';

  @override
  String couldNotLoadPdf(String error) {
    return 'Could not load this PDF.\n$error';
  }

  @override
  String get renderingPdf => 'Rendering PDF…';

  @override
  String couldNotRenderPdf(String error) {
    return 'Could not render this PDF.\n$error';
  }

  @override
  String get loadingText => 'Loading text…';

  @override
  String couldNotLoadFile(String error) {
    return 'Could not load this file.\n$error';
  }

  @override
  String couldNotLoadVideo(String error) {
    return 'Could not load this video.\n$error';
  }

  @override
  String couldNotLoadAudio(String error) {
    return 'Could not load this audio.\n$error';
  }

  @override
  String get connectionLost =>
      'Connection lost — check your network and try again.';

  @override
  String couldNotLoadDrives(String error) {
    return 'Could not load drives: $error';
  }

  @override
  String driveInfoFreeOfTotal(String free, String total, String path) {
    return '$free free of $total  ·  $path';
  }

  @override
  String get alreadyInThisFolder => 'Already in this folder';

  @override
  String clipboardAllExistNothing(String folder, String operation) {
    return 'All clipboard items already exist in $folder — nothing to $operation';
  }

  @override
  String get renamedLabel => 'Renamed';

  @override
  String get emptyFolderMessage => 'This folder is empty';

  @override
  String get noMatchesMessage => 'No items match the current filter';

  @override
  String get offlineBannerText => 'Offline — showing cached files';

  @override
  String get defaultsApplyHint =>
      'These defaults apply to every device. Override any of them for a single device from that device’s settings.';

  @override
  String get themeLabel => 'Theme';

  @override
  String get wallpaperSubtitle =>
      'Material You — derive the palette from your wallpaper where supported';

  @override
  String get languageLabel => 'Language';

  @override
  String get sortFieldName => 'Name';

  @override
  String get sortFieldSize => 'Size';

  @override
  String get sortFieldDate => 'Date modified';

  @override
  String get sortFieldType => 'Type';

  @override
  String get invalidQrFormat => 'Invalid QR code format.';

  @override
  String get qrMissingFields => 'QR missing required fields.';

  @override
  String get sendViaQrButton => 'Send via QR';

  @override
  String get qrHandoffSheetTitle => 'Scan to receive';

  @override
  String get qrHandoffNoFingerprint =>
      'Can\'t share — this host has no pinned certificate.';

  @override
  String get receiveFileTooltip => 'Receive file';

  @override
  String get receiveFileTitle => 'Receive file';

  @override
  String get qrHandoffNoHostMatch =>
      'You\'re not paired to this PC — pair first, then scan again.';

  @override
  String get backUpNow => 'Back up now';

  @override
  String get scanningStatus => 'Scanning…';

  @override
  String backingUpPhotos(int count) {
    return 'Backing up $count photo(s)';
  }

  @override
  String get alreadyUpToDate => 'Already up to date';

  @override
  String get pickPcFirst => 'Pick a PC first';

  @override
  String get serverDestNotConfigured =>
      'This PC hasn\'t set a photo backup destination yet — set one in its web companion Settings';

  @override
  String get photoAccessDenied =>
      'Photo access denied — grant it in system settings';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get noPairedPcs => 'No paired PCs — pair one first';

  @override
  String get choosePc => 'Choose a PC';

  @override
  String get backupRecordCleared => 'Backup record cleared';

  @override
  String get resetBackupHint =>
      'Tap to forget the record (re-backs-up everything)';

  @override
  String get deviceNicknameHelper =>
      'Optional. Tells your photos apart from other phones backing up to the same PC.';

  @override
  String preparingToShare(String name) {
    return 'Preparing $name to share…';
  }

  @override
  String couldNotShare(String name) {
    return 'Could not share $name';
  }

  @override
  String get openWithTooltip => 'Open with…';

  @override
  String get openWithButton => 'Open with…';

  @override
  String preparingToOpen(String name) {
    return 'Preparing $name…';
  }

  @override
  String couldNotOpen(String name) {
    return 'Could not open $name';
  }

  @override
  String savingFile(String name) {
    return 'Saving $name…';
  }

  @override
  String fileTooLargeToPreview(String sizeLabel) {
    return 'This file is too large to preview ($sizeLabel).\nDownload it to view it instead.';
  }

  @override
  String get readOnlyModeSaveError =>
      'This host is in read-only mode — changes can’t be saved.';

  @override
  String get fileTooLargeToSave => 'This file is too large to save.';

  @override
  String get staleWriteMessage =>
      'This file was modified on the host since you opened it. You can reload the current version (your edits here will be lost) or overwrite it with your edits.';

  @override
  String get reloadedFromHost => 'Reloaded the current version from the host';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get includeHiddenSubtitle =>
      'Also show results hidden by file visibility settings';

  @override
  String get writesRejected => 'Writes are rejected';

  @override
  String get phoneCanModify => 'This phone can modify files';

  @override
  String get allFoldersAllowed => 'All folders allowed';

  @override
  String get securityWarning =>
      'This phone has full control of the host. Anyone with access to it can change these settings and reach allowed folders.';

  @override
  String get thisDevice => 'This device';

  @override
  String get revokedStatus => 'Revoked';

  @override
  String get activeStatus => 'Active';

  @override
  String limitedTo(String path) {
    return 'Limited to: $path';
  }

  @override
  String get managedOnPc => 'Managed on the PC';

  @override
  String get osLabel => 'OS';

  @override
  String driveCapacityLine(String used, String total, String free) {
    return 'Used $used of $total · $free free';
  }

  @override
  String driveCapacityLineOs(String used, String total, String free) {
    return 'Used $used of $total · $free free · contains the OS';
  }

  @override
  String addedFolder(String path) {
    return 'Added $path';
  }

  @override
  String removedFolder(String path) {
    return 'Removed $path';
  }

  @override
  String disconnectFailed(String error) {
    return 'Disconnect failed: $error';
  }

  @override
  String disconnectDeviceMessage(String pcName) {
    return 'Disconnect this device from $pcName? You’ll need a new pairing code to reconnect.';
  }

  @override
  String get noCustomExtensions => 'None — add an extension below.';

  @override
  String get passphraseMismatch => 'Passphrases do not match';

  @override
  String get passphraseMinLength => 'Passphrase must be at least 6 characters';

  @override
  String get usingDeviceVisibility => 'Using device-specific visibility';

  @override
  String get usingAppDefault => 'Using app default';

  @override
  String get followsAppDefaultVisibility =>
      'Follows your app-default file visibility unless you override it here.';

  @override
  String get overriddenForDevice => 'Overridden for this device';

  @override
  String usingAppDefaultLabel(String label) {
    return 'Using app default ($label)';
  }

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String get updateNotCompleted => 'Update not completed — tap to retry.';

  @override
  String get openingInstallerConfirm =>
      'Opening installer — confirm in Android, then return here.';

  @override
  String get downloadPaused =>
      'Download paused. Retry to resume where it left off.';

  @override
  String get exportConfigSubtitle =>
      'Save paired hosts, tokens, favorites, and settings to an encrypted file';

  @override
  String get backupEncryptionWarning =>
      'Backups are encrypted with your passphrase. If you lose it, the backup cannot be recovered.';

  @override
  String get preparingBackup => 'Preparing backup…';

  @override
  String get backupReadyToShare => 'Backup ready to share';

  @override
  String get exportFailed => 'Export failed';

  @override
  String couldNotReadFile(String error) {
    return 'Could not read file: $error';
  }

  @override
  String get importWarningMessage =>
      'Importing replaces all current hosts, tokens, and settings on this device. Continue?';

  @override
  String get restoringConfig => 'Restoring config…';

  @override
  String get configRestored =>
      'Config restored. For best results, fully close and reopen the app.';

  @override
  String get importFailed => 'Import failed';

  @override
  String get ascendingTooltip => 'Ascending';

  @override
  String get descendingTooltip => 'Descending';

  @override
  String get pausedStatus => 'Paused';

  @override
  String get verifiedLabel => 'Verified';

  @override
  String get metaPath => 'Path';

  @override
  String get metaSize => 'Size';

  @override
  String get metaType => 'Type';

  @override
  String get metaPermissions => 'Permissions';

  @override
  String get metaModified => 'Modified';

  @override
  String get metaCreated => 'Created';

  @override
  String get metaSymlink => 'Symlink';

  @override
  String get noLabel => 'No';

  @override
  String couldNotDuplicate(String name) {
    return 'Couldn\'t duplicate \"$name\"';
  }

  @override
  String restoredItem(String name) {
    return 'Restored \"$name\"';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String deleteForeverConfirm(String name) {
    return 'Permanently delete \"$name\"? This cannot be undone.';
  }

  @override
  String deletedForever(String name) {
    return 'Deleted \"$name\" forever';
  }

  @override
  String emptyTrashBody(int count) {
    return 'Permanently delete all $count item(s)? This cannot be undone.';
  }

  @override
  String get trashEmptied => 'Trash emptied';

  @override
  String emptyFailed(String error) {
    return 'Empty failed: $error';
  }

  @override
  String get trashIsEmpty => 'Trash is empty';

  @override
  String get trashEmptySubtitle =>
      'Deleted items appear here and can be restored.';

  @override
  String deletedRelative(String relative) {
    return 'deleted $relative';
  }

  @override
  String copyItemsTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return 'Copy $count $_temp0 to…';
  }

  @override
  String moveItemsTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items',
      one: 'item',
    );
    return 'Move $count $_temp0 to…';
  }

  @override
  String get copyHereButton => 'Copy here';

  @override
  String get moveHereButton => 'Move here';

  @override
  String get downloadingEllipsis => 'Downloading…';

  @override
  String get transfersTitle => 'Transfers';

  @override
  String get transferGroupActive => 'Active';

  @override
  String get transferGroupQueued => 'Queued';

  @override
  String get transferGroupDone => 'Done';

  @override
  String get transferGroupFailed => 'Failed';

  @override
  String get followsDefaultsOverrideHint =>
      'These follow your app defaults unless you override them here.';

  @override
  String get importReplacesBody =>
      'Importing replaces all current hosts, tokens, and settings on this device. Continue?';

  @override
  String get searchCategoryFolders => 'Folders';

  @override
  String get searchCategoryImages => 'Images';

  @override
  String get searchCategoryVideos => 'Videos';

  @override
  String get searchCategoryAudio => 'Audio';

  @override
  String get searchCategoryDocs => 'Docs';

  @override
  String get searchCategoryArchives => 'Archives';

  @override
  String get searchCategoryOther => 'Other';

  @override
  String get sizePresetAny => 'Any size';

  @override
  String get sizePresetMb1 => '> 1 MB';

  @override
  String get sizePresetMb10 => '> 10 MB';

  @override
  String get sizePresetMb100 => '> 100 MB';

  @override
  String get sizePresetGb1 => '> 1 GB';

  @override
  String get datePresetAny => 'Any time';

  @override
  String get datePresetLast24h => 'Last 24 hours';

  @override
  String get datePresetLast7d => 'Last 7 days';

  @override
  String get datePresetLast30d => 'Last 30 days';

  @override
  String get datePresetThisYear => 'This year';

  @override
  String get wakeButton => 'Wake';

  @override
  String wolPacketSent(String hostname) {
    return 'Magic packet sent to $hostname';
  }

  @override
  String get wolPacketFailed => 'Failed to send magic packet';

  @override
  String previewPageIndicator(int current, int total) {
    return '$current of $total';
  }

  @override
  String get bandwidthSection => 'Bandwidth';

  @override
  String get bandwidthUploadLimit => 'Upload limit';

  @override
  String get bandwidthDownloadLimit => 'Download limit';

  @override
  String get bandwidthUnlimited => 'Unlimited';

  @override
  String get cacheSection => 'Cache';

  @override
  String get cacheListingLabel => 'Listing cache';

  @override
  String get cacheTempLabel => 'Downloaded files';

  @override
  String get cacheTotalLabel => 'Total';

  @override
  String get cacheClearAll => 'Clear all cache';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String get cacheCalculating => 'Calculating…';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Remote File Explorer';

  @override
  String get onboardingWelcomeBody =>
      'Browse, manage, and transfer files between your phone and any PC on your network.';

  @override
  String get onboardingHowTitle => 'How it works';

  @override
  String get onboardingHowBody =>
      'Install the agent on your PC, pair it with this app using a one-time code, and you\'re connected — over Wi-Fi or Tailscale.';

  @override
  String get onboardingReadyTitle => 'Ready to go';

  @override
  String get onboardingReadyBody =>
      'Pair your first PC to start exploring. Your files stay on your devices — nothing goes to the cloud.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get notificationsSection => 'Notifications';

  @override
  String get transferNotifications => 'Transfer notifications';

  @override
  String get transferNotificationsSubtitle =>
      'Show a notification when transfers complete';

  @override
  String get lowDiskAlerts => 'Low disk alerts';

  @override
  String get lowDiskAlertsSubtitle =>
      'Show a warning when a drive has less than 1 GB free';

  @override
  String get lowDiskWarning => 'Low disk space';

  @override
  String get wolRelayFailed => 'Could not wake via relay';

  @override
  String wolRelaySent(String relayHost) {
    return 'Wake packet sent via $relayHost';
  }

  @override
  String get savedSearches => 'Saved searches';

  @override
  String get saveSearch => 'Save search';

  @override
  String get savedSearchName => 'Name';

  @override
  String get noSavedSearches => 'No saved searches yet';

  @override
  String get deleteSavedSearch => 'Delete saved search';

  @override
  String get searchModeSubstring => 'Contains';

  @override
  String get searchModeGlob => 'Glob';

  @override
  String get searchModeRegex => 'Regex';

  @override
  String get diagnosticsExportTitle => 'Diagnostics';

  @override
  String get diagnosticsExportButton => 'Export diagnostics';

  @override
  String get diagnosticsExportSubtitle =>
      'Share device and connection info for troubleshooting';

  @override
  String get diagnosticsCopied => 'Diagnostics copied to clipboard';

  @override
  String get audioSpeedLabel => 'Speed';

  @override
  String audioSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String audioDownloadingProgress(String percent) {
    return 'Downloading audio for preview… $percent%';
  }

  @override
  String get storageByTypeTitle => 'Storage by type';

  @override
  String get sseConnected => 'Live';

  @override
  String get chmodTitle => 'Permissions';

  @override
  String get chmodOwner => 'Owner';

  @override
  String get chmodGroup => 'Group';

  @override
  String get chmodOther => 'Other';

  @override
  String get discoveredHosts => 'Discovered on network';

  @override
  String get archiveContents => 'Archive Contents';

  @override
  String get archiveEmpty => 'Empty archive';

  @override
  String archiveEntries(int count) {
    return '$count entries';
  }

  @override
  String get dupFinderTitle => 'Find Duplicates';

  @override
  String get dupFinderScreenTitle => 'Duplicate Finder';

  @override
  String get dupFinderScan => 'Scan for Duplicates';

  @override
  String dupFinderScanning(int count) {
    return 'Scanning $count files...';
  }

  @override
  String get dupFinderNone => 'No duplicates found';

  @override
  String get syncRulesTitle => 'Sync Rules';

  @override
  String get syncRulesSubtitle => 'Download remote folders to local storage';

  @override
  String get syncAddRule => 'Add Sync Rule';

  @override
  String get syncDeleteRule => 'Delete Sync Rule';

  @override
  String get syncDeleteConfirm => 'Delete this sync rule?';

  @override
  String get syncNow => 'Sync Now';

  @override
  String get syncNever => 'Never synced';

  @override
  String get syncNoRules => 'No sync rules yet';

  @override
  String get syncRemotePath => 'Remote Path';

  @override
  String get syncLocalPath => 'Local Folder';

  @override
  String get crossHostSearchTitle => 'Search All Hosts';

  @override
  String get crossHostSearchHint => 'Search all hosts...';

  @override
  String crossHostSearching(int count) {
    return 'Searching $count hosts...';
  }

  @override
  String get crossHostNoResults => 'No results';

  @override
  String get crossHostTypeToSearch => 'Type to search across all hosts';

  @override
  String get crossHostSearchTooltip => 'Search all hosts';

  @override
  String get commandPaletteTitle => 'Command Palette';

  @override
  String get commandPaletteHint => 'Type a command...';

  @override
  String get goToPathTitle => 'Go to Path';
}
