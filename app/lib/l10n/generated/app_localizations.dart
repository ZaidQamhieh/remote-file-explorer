import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote File Explorer'**
  String get appTitle;

  /// No description provided for @browseButton.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browseButton;

  /// No description provided for @searchButton.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchButton;

  /// No description provided for @moreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// No description provided for @appSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get appSettingsTooltip;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @closeButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// No description provided for @addButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButton;

  /// No description provided for @createButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createButton;

  /// No description provided for @applyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyButton;

  /// No description provided for @resetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetButton;

  /// No description provided for @updateButton.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateButton;

  /// No description provided for @dismissButton.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismissButton;

  /// No description provided for @undoButton.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoButton;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @replaceButton.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replaceButton;

  /// No description provided for @discardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// No description provided for @pairButton.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pairButton;

  /// No description provided for @onlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineStatus;

  /// No description provided for @offlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offlineStatus;

  /// No description provided for @checkingStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checkingStatus;

  /// No description provided for @networkLan.
  ///
  /// In en, this message translates to:
  /// **'LAN'**
  String get networkLan;

  /// No description provided for @networkTailscale.
  ///
  /// In en, this message translates to:
  /// **'Tailscale'**
  String get networkTailscale;

  /// No description provided for @hostSubtitleVersionNetwork.
  ///
  /// In en, this message translates to:
  /// **'v{version} · {network}'**
  String hostSubtitleVersionNetwork(String version, String network);

  /// No description provided for @statusCheckedRelative.
  ///
  /// In en, this message translates to:
  /// **'Checked {relative}'**
  String statusCheckedRelative(String relative);

  /// No description provided for @statusOfflineLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Offline · last seen {relative}'**
  String statusOfflineLastSeen(String relative);

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeJustNow;

  /// No description provided for @relativeSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}s ago'**
  String relativeSecondsAgo(int count);

  /// No description provided for @relativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String relativeMinutesAgo(int count);

  /// No description provided for @relativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String relativeHoursAgo(int count);

  /// No description provided for @relativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String relativeDaysAgo(int count);

  /// No description provided for @couldNotReachComputer.
  ///
  /// In en, this message translates to:
  /// **'Could not reach this computer.'**
  String get couldNotReachComputer;

  /// No description provided for @forgetComputerTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this computer?'**
  String get forgetComputerTitle;

  /// No description provided for @forgetComputerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{hostLabel}\"? You can re-add it later.'**
  String forgetComputerConfirm(String hostLabel);

  /// No description provided for @forgetButton.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forgetButton;

  /// No description provided for @forgetComputerMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Forget this computer'**
  String get forgetComputerMenuItem;

  /// No description provided for @storageMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageMenuItem;

  /// No description provided for @transfersMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfersMenuItem;

  /// No description provided for @diagnosticsMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsMenuItem;

  /// No description provided for @settingsMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsMenuItem;

  /// No description provided for @nMoreDrives.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String nMoreDrives(int count);

  /// No description provided for @addComputerButton.
  ///
  /// In en, this message translates to:
  /// **'Add computer'**
  String get addComputerButton;

  /// No description provided for @scanQrCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCodeButton;

  /// No description provided for @emptyStatePairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair your first PC'**
  String get emptyStatePairTitle;

  /// No description provided for @emptyStatePairBody.
  ///
  /// In en, this message translates to:
  /// **'Scan the pairing QR code shown by the desktop agent to connect this phone over your network or Tailscale.'**
  String get emptyStatePairBody;

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(String error);

  /// No description provided for @connectionDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Diagnostics'**
  String get connectionDiagnosticsTitle;

  /// No description provided for @retestButton.
  ///
  /// In en, this message translates to:
  /// **'Re-test'**
  String get retestButton;

  /// No description provided for @probeTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get probeTimedOut;

  /// No description provided for @probeError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get probeError;

  /// No description provided for @probeLatencyMs.
  ///
  /// In en, this message translates to:
  /// **'{ms}ms'**
  String probeLatencyMs(int ms);

  /// No description provided for @hostStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'{hostLabel} · Storage'**
  String hostStorageTitle(String hostLabel);

  /// No description provided for @allDrives.
  ///
  /// In en, this message translates to:
  /// **'All drives'**
  String get allDrives;

  /// No description provided for @couldNotLoadStorage.
  ///
  /// In en, this message translates to:
  /// **'Could not load storage: {error}'**
  String couldNotLoadStorage(String error);

  /// No description provided for @freeOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{free} free of {total}'**
  String freeOfTotal(String free, String total);

  /// No description provided for @freeOfTotalDrives.
  ///
  /// In en, this message translates to:
  /// **'{free} free of {total} · {count, plural, =1{1 drive} other{{count} drives}}'**
  String freeOfTotalDrives(String free, String total, int count);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files and folders…'**
  String get searchHint;

  /// No description provided for @clearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearTooltip;

  /// No description provided for @searchFiltersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search filters'**
  String get searchFiltersTooltip;

  /// No description provided for @activeFilterCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String activeFilterCount(int count);

  /// No description provided for @globPattern.
  ///
  /// In en, this message translates to:
  /// **'Glob pattern'**
  String get globPattern;

  /// No description provided for @clearAllButton.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllButton;

  /// No description provided for @removeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeTooltip;

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get fileSize;

  /// No description provided for @searchScope.
  ///
  /// In en, this message translates to:
  /// **'Search scope'**
  String get searchScope;

  /// No description provided for @fromHere.
  ///
  /// In en, this message translates to:
  /// **'From here'**
  String get fromHere;

  /// No description provided for @everywhere.
  ///
  /// In en, this message translates to:
  /// **'Everywhere'**
  String get everywhere;

  /// No description provided for @includeHiddenItems.
  ///
  /// In en, this message translates to:
  /// **'Include hidden items'**
  String get includeHiddenItems;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(String error);

  /// No description provided for @noResultsFor.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\".'**
  String noResultsFor(String query);

  /// No description provided for @typeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search for files and folders by name.'**
  String get typeToSearch;

  /// No description provided for @showingFirstNResults.
  ///
  /// In en, this message translates to:
  /// **'Showing first {limit} results — refine your search.'**
  String showingFirstNResults(int limit);

  /// No description provided for @searchTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Search timed out — showing partial results.'**
  String get searchTimedOut;

  /// No description provided for @searchingIn.
  ///
  /// In en, this message translates to:
  /// **'Searching in: {path}'**
  String searchingIn(String path);

  /// No description provided for @searchingEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Searching everywhere'**
  String get searchingEverywhere;

  /// No description provided for @searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTooltip;

  /// No description provided for @clearSelectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelectionTooltip;

  /// No description provided for @batchRenameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Batch rename'**
  String get batchRenameTooltip;

  /// No description provided for @invertSelectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Invert selection'**
  String get invertSelectionTooltip;

  /// No description provided for @selectAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAllTooltip;

  /// No description provided for @deselectAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAllTooltip;

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelected(int count);

  /// No description provided for @uploadFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get uploadFileTooltip;

  /// No description provided for @newButton.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newButton;

  /// No description provided for @favoriteFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Favorite this folder'**
  String get favoriteFolderTooltip;

  /// No description provided for @removeFavoriteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite'**
  String get removeFavoriteTooltip;

  /// No description provided for @viewOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'View options'**
  String get viewOptionsTitle;

  /// No description provided for @layoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutLabel;

  /// No description provided for @listLabel.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get listLabel;

  /// No description provided for @gridLabel.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get gridLabel;

  /// No description provided for @densityLabel.
  ///
  /// In en, this message translates to:
  /// **'Density'**
  String get densityLabel;

  /// No description provided for @comfortableLabel.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get comfortableLabel;

  /// No description provided for @compactLabel.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get compactLabel;

  /// No description provided for @sortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortByLabel;

  /// No description provided for @showHiddenItems.
  ///
  /// In en, this message translates to:
  /// **'Show hidden items'**
  String get showHiddenItems;

  /// No description provided for @nHiddenByVisibility.
  ///
  /// In en, this message translates to:
  /// **'{count} hidden by file visibility settings'**
  String nHiddenByVisibility(int count);

  /// No description provided for @newFolderButton.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolderButton;

  /// No description provided for @newFileButton.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get newFileButton;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameHint;

  /// No description provided for @createdName.
  ///
  /// In en, this message translates to:
  /// **'Created {name}'**
  String createdName(String name);

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create {name}: {error}'**
  String createFailed(String name, String error);

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet. Open a folder and tap the star to bookmark it.'**
  String get noFavoritesYet;

  /// No description provided for @cancelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelTooltip;

  /// No description provided for @nameConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Name conflict'**
  String get nameConflictTitle;

  /// No description provided for @nameConflictBody.
  ///
  /// In en, this message translates to:
  /// **'{collidingCount} of {totalCount} {totalCount, plural, =1{item} other{items}} already exist in {dest}.'**
  String nameConflictBody(int collidingCount, int totalCount, String dest);

  /// No description provided for @skipTheseButton.
  ///
  /// In en, this message translates to:
  /// **'Skip these'**
  String get skipTheseButton;

  /// No description provided for @keepBothButton.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get keepBothButton;

  /// No description provided for @overwriteButton.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwriteButton;

  /// No description provided for @previewButton.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewButton;

  /// No description provided for @downloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadButton;

  /// No description provided for @extractHereButton.
  ///
  /// In en, this message translates to:
  /// **'Extract here'**
  String get extractHereButton;

  /// No description provided for @renameButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameButton;

  /// No description provided for @duplicateButton.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @newNameLabel.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get newNameLabel;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get deleteTitle;

  /// No description provided for @deleteForeverButton.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteForeverButton;

  /// No description provided for @moveToTrashButton.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrashButton;

  /// No description provided for @favoriteButton.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteButton;

  /// No description provided for @unfavoriteButton.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavoriteButton;

  /// No description provided for @yesLabel.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yesLabel;

  /// No description provided for @copiedPath.
  ///
  /// In en, this message translates to:
  /// **'Copied \"{path}\"'**
  String copiedPath(String path);

  /// No description provided for @copyPathAction.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPathAction;

  /// No description provided for @pastePathAction.
  ///
  /// In en, this message translates to:
  /// **'Paste path'**
  String get pastePathAction;

  /// No description provided for @clipboardEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmptyMessage;

  /// No description provided for @removedFavorite.
  ///
  /// In en, this message translates to:
  /// **'Removed \"{name}\" from favorites'**
  String removedFavorite(String name);

  /// No description provided for @addedFavorite.
  ///
  /// In en, this message translates to:
  /// **'Added \"{name}\" to favorites'**
  String addedFavorite(String name);

  /// No description provided for @downloadingFile.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}…'**
  String downloadingFile(String name);

  /// No description provided for @renamedTo.
  ///
  /// In en, this message translates to:
  /// **'Renamed to {newName}'**
  String renamedTo(String newName);

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String renameFailed(String error);

  /// No description provided for @duplicatedFile.
  ///
  /// In en, this message translates to:
  /// **'Duplicated \"{name}\"'**
  String duplicatedFile(String name);

  /// No description provided for @duplicateFailed.
  ///
  /// In en, this message translates to:
  /// **'Duplicate failed: {error}'**
  String duplicateFailed(String error);

  /// No description provided for @extractedFile.
  ///
  /// In en, this message translates to:
  /// **'Extracted \"{name}\"'**
  String extractedFile(String name);

  /// No description provided for @extractFailed.
  ///
  /// In en, this message translates to:
  /// **'Extract failed: {error}'**
  String extractFailed(String error);

  /// No description provided for @moveToTrashConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to Trash? You can restore it later.'**
  String moveToTrashConfirm(String name);

  /// No description provided for @deletedName.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedName(String name);

  /// No description provided for @movedToTrashName.
  ///
  /// In en, this message translates to:
  /// **'Moved {name} to Trash'**
  String movedToTrashName(String name);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @folderDetailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Folder details'**
  String get folderDetailsTooltip;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashTitle;

  /// No description provided for @emptyTrashTooltip.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get emptyTrashTooltip;

  /// No description provided for @deleteForeverTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete forever?'**
  String get deleteForeverTitle;

  /// No description provided for @emptyTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty trash?'**
  String get emptyTrashTitle;

  /// No description provided for @restoreButton.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreButton;

  /// No description provided for @patternLabel.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get patternLabel;

  /// No description provided for @findAndReplaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Find & replace'**
  String get findAndReplaceLabel;

  /// No description provided for @baseNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Base name'**
  String get baseNameLabel;

  /// No description provided for @startNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Start number'**
  String get startNumberLabel;

  /// No description provided for @findLabel.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findLabel;

  /// No description provided for @replaceWithLabel.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get replaceWithLabel;

  /// No description provided for @renameNItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename {count} items'**
  String renameNItemsTitle(int count);

  /// No description provided for @renameNItems.
  ///
  /// In en, this message translates to:
  /// **'Rename {count}'**
  String renameNItems(int count);

  /// No description provided for @baseNameHelperText.
  ///
  /// In en, this message translates to:
  /// **'Place the number with the n token; else it\'\'s appended.'**
  String get baseNameHelperText;

  /// No description provided for @andNMore.
  ///
  /// In en, this message translates to:
  /// **'… and {count} more'**
  String andNMore(int count);

  /// No description provided for @batchSuccessNItems.
  ///
  /// In en, this message translates to:
  /// **'{verb} {count} {count, plural, =1{item} other{items}}'**
  String batchSuccessNItems(String verb, int count);

  /// No description provided for @batchResultWithErrors.
  ///
  /// In en, this message translates to:
  /// **'{verb} with {errorCount} error(s)'**
  String batchResultWithErrors(String verb, int errorCount);

  /// No description provided for @cutButton.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cutButton;

  /// No description provided for @copyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButton;

  /// No description provided for @compressButton.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressButton;

  /// No description provided for @moveNItemsToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move {count} {count, plural, =1{item} other{items}} to Trash?'**
  String moveNItemsToTrash(int count);

  /// No description provided for @canRestoreFromTrash.
  ///
  /// In en, this message translates to:
  /// **'You can restore {count, plural, =1{it} other{them}} from Trash.'**
  String canRestoreFromTrash(int count);

  /// No description provided for @compressedTo.
  ///
  /// In en, this message translates to:
  /// **'Compressed to {name}'**
  String compressedTo(String name);

  /// No description provided for @compressFailed.
  ///
  /// In en, this message translates to:
  /// **'Compress failed: {error}'**
  String compressFailed(String error);

  /// No description provided for @queuedNDownloads.
  ///
  /// In en, this message translates to:
  /// **'Queued {count} {count, plural, =1{download} other{downloads}}'**
  String queuedNDownloads(int count);

  /// No description provided for @deletedLabel.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deletedLabel;

  /// No description provided for @movedToTrashLabel.
  ///
  /// In en, this message translates to:
  /// **'Moved to Trash'**
  String get movedToTrashLabel;

  /// No description provided for @clipboardCopiedHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} copied — open a folder and tap Paste'**
  String clipboardCopiedHint(int count);

  /// No description provided for @clipboardCutHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} cut — open a folder and tap Paste'**
  String clipboardCutHint(int count);

  /// No description provided for @pasteNItems.
  ///
  /// In en, this message translates to:
  /// **'Paste {count} {count, plural, =1{item} other{items}}'**
  String pasteNItems(int count);

  /// No description provided for @movedLabel.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get movedLabel;

  /// No description provided for @copiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedLabel;

  /// No description provided for @moveLabel.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveLabel;

  /// No description provided for @copyLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyLabel;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'{operation} failed: {error}'**
  String operationFailed(String operation, String error);

  /// No description provided for @alreadyExistsSkipped.
  ///
  /// In en, this message translates to:
  /// **'{name} already exists — skipped'**
  String alreadyExistsSkipped(String name);

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading {name}…'**
  String uploadingFile(String name);

  /// No description provided for @nHidden.
  ///
  /// In en, this message translates to:
  /// **'{count} hidden'**
  String nHidden(int count);

  /// No description provided for @hideLabel.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideLabel;

  /// No description provided for @showLabel.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showLabel;

  /// No description provided for @itemExistsInFolder.
  ///
  /// In en, this message translates to:
  /// **'{name} already exists in {folder}'**
  String itemExistsInFolder(String name, String folder);

  /// No description provided for @couldNotCheckFolder.
  ///
  /// In en, this message translates to:
  /// **'Could not check {folder} for existing items: {error}'**
  String couldNotCheckFolder(String folder, String error);

  /// No description provided for @movedFile.
  ///
  /// In en, this message translates to:
  /// **'Moved {name}'**
  String movedFile(String name);

  /// No description provided for @moveFailed.
  ///
  /// In en, this message translates to:
  /// **'Move failed: {error}'**
  String moveFailed(String error);

  /// No description provided for @nothingToPaste.
  ///
  /// In en, this message translates to:
  /// **'{folder} — nothing to {operation}'**
  String nothingToPaste(String folder, String operation);

  /// No description provided for @pathLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} · '**
  String pathLabel(String label);

  /// No description provided for @showHiddenFoldersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show hidden folders'**
  String get showHiddenFoldersTooltip;

  /// No description provided for @addComputerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add computer'**
  String get addComputerTitle;

  /// No description provided for @scanQrTab.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrTab;

  /// No description provided for @manualTab.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manualTab;

  /// No description provided for @loginTab.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginTab;

  /// No description provided for @agentAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent address'**
  String get agentAddressLabel;

  /// No description provided for @agentAddressHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.10:8765'**
  String get agentAddressHint;

  /// No description provided for @pairingCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCodeLabel;

  /// No description provided for @pairingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'123456'**
  String get pairingCodeHint;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginButton;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {error}'**
  String loginFailed(String error);

  /// No description provided for @loginHint.
  ///
  /// In en, this message translates to:
  /// **'No account yet? Run \"rfe-agent adduser <username>\" on the PC once, then log in from any device.'**
  String get loginHint;

  /// No description provided for @requiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredLabel;

  /// No description provided for @pairedWith.
  ///
  /// In en, this message translates to:
  /// **'Paired with {name}'**
  String pairedWith(String name);

  /// No description provided for @fingerprintMismatch.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint mismatch: {error}'**
  String fingerprintMismatch(String error);

  /// No description provided for @pairingFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: {error}'**
  String pairingFailed(String error);

  /// No description provided for @photoBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo backup'**
  String get photoBackupTitle;

  /// No description provided for @enablePhotoBackup.
  ///
  /// In en, this message translates to:
  /// **'Enable photo backup'**
  String get enablePhotoBackup;

  /// No description provided for @photoBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One-way: copies new photos to your PC'**
  String get photoBackupSubtitle;

  /// No description provided for @backUpTo.
  ///
  /// In en, this message translates to:
  /// **'Back up to'**
  String get backUpTo;

  /// No description provided for @destinationFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination folder on PC'**
  String get destinationFolderLabel;

  /// No description provided for @destinationFolderHint.
  ///
  /// In en, this message translates to:
  /// **'/home/you/PhoneBackup'**
  String get destinationFolderHint;

  /// No description provided for @onlyOnWifi.
  ///
  /// In en, this message translates to:
  /// **'Only on Wi-Fi'**
  String get onlyOnWifi;

  /// No description provided for @onlyWhileCharging.
  ///
  /// In en, this message translates to:
  /// **'Only while charging'**
  String get onlyWhileCharging;

  /// No description provided for @photosBackedUp.
  ///
  /// In en, this message translates to:
  /// **'{count} photo(s) backed up'**
  String photosBackedUp(int count);

  /// No description provided for @shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTooltip;

  /// No description provided for @shareLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLinkButton;

  /// No description provided for @shareLinkSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLinkSheetTitle;

  /// No description provided for @shareLinkExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String shareLinkExpiresIn(String time);

  /// No description provided for @shareLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'Link expired'**
  String get shareLinkExpired;

  /// No description provided for @shareLinkRevokeButton.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get shareLinkRevokeButton;

  /// No description provided for @shareLinkRevoked.
  ///
  /// In en, this message translates to:
  /// **'Share link revoked'**
  String get shareLinkRevoked;

  /// No description provided for @shareLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Share link failed: {error}'**
  String shareLinkFailed(String error);

  /// No description provided for @saveToDeviceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToDeviceTooltip;

  /// No description provided for @showInFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get showInFolderTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @fileChangedOnDisk.
  ///
  /// In en, this message translates to:
  /// **'File changed on disk'**
  String get fileChangedOnDisk;

  /// No description provided for @reloadButton.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reloadButton;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes that will be lost.'**
  String get unsavedChangesMessage;

  /// No description provided for @keepEditingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditingButton;

  /// No description provided for @saveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveTooltip;

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String savedFile(String name);

  /// No description provided for @couldNotSaveFile.
  ///
  /// In en, this message translates to:
  /// **'Could not save this file.\n{error}'**
  String couldNotSaveFile(String error);

  /// No description provided for @couldNotReloadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not reload this file.\n{error}'**
  String couldNotReloadFile(String error);

  /// No description provided for @editTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editTooltip;

  /// No description provided for @hideLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Hide line numbers'**
  String get hideLineNumbers;

  /// No description provided for @appSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get appSettingsTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @useWallpaperColors.
  ///
  /// In en, this message translates to:
  /// **'Use wallpaper colors'**
  String get useWallpaperColors;

  /// No description provided for @displaySection.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displaySection;

  /// No description provided for @updatesSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesSection;

  /// No description provided for @photoBackupSection.
  ///
  /// In en, this message translates to:
  /// **'Photo backup'**
  String get photoBackupSection;

  /// No description provided for @copyPhonePhotos.
  ///
  /// In en, this message translates to:
  /// **'Copy phone photos to a PC'**
  String get copyPhonePhotos;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @agentSection.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentSection;

  /// No description provided for @agentNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get agentNameLabel;

  /// No description provided for @accessSection.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get accessSection;

  /// No description provided for @readOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Read-only mode'**
  String get readOnlyMode;

  /// No description provided for @enableShareLinks.
  ///
  /// In en, this message translates to:
  /// **'Enable share links'**
  String get enableShareLinks;

  /// No description provided for @shareLinksEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Files can be shared via one-time links'**
  String get shareLinksEnabledHint;

  /// No description provided for @shareLinksDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Share links are turned off'**
  String get shareLinksDisabledHint;

  /// No description provided for @allowedFoldersSection.
  ///
  /// In en, this message translates to:
  /// **'Allowed folders'**
  String get allowedFoldersSection;

  /// No description provided for @addFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolderTooltip;

  /// No description provided for @removeFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove folder'**
  String get removeFolderTooltip;

  /// No description provided for @pairedDevicesSection.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get pairedDevicesSection;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @pcNameLabel.
  ///
  /// In en, this message translates to:
  /// **'PC name'**
  String get pcNameLabel;

  /// No description provided for @disconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectButton;

  /// No description provided for @disconnectDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect this device?'**
  String get disconnectDeviceTitle;

  /// No description provided for @addAllowedFolder.
  ///
  /// In en, this message translates to:
  /// **'Add allowed folder'**
  String get addAllowedFolder;

  /// No description provided for @allowedFolderHint.
  ///
  /// In en, this message translates to:
  /// **'/home/me/Documents'**
  String get allowedFolderHint;

  /// No description provided for @renameAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename agent'**
  String get renameAgentTitle;

  /// No description provided for @hideDotfiles.
  ///
  /// In en, this message translates to:
  /// **'Hide dotfiles'**
  String get hideDotfiles;

  /// No description provided for @hideDotfilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide files and folders starting with \".\"'**
  String get hideDotfilesSubtitle;

  /// No description provided for @customLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customLabel;

  /// No description provided for @dotExtension.
  ///
  /// In en, this message translates to:
  /// **'.{ext}'**
  String dotExtension(String ext);

  /// No description provided for @fileVisibilitySection.
  ///
  /// In en, this message translates to:
  /// **'File visibility'**
  String get fileVisibilitySection;

  /// No description provided for @fileVisibilityDeviceSection.
  ///
  /// In en, this message translates to:
  /// **'File visibility (this device)'**
  String get fileVisibilityDeviceSection;

  /// No description provided for @overrideForDevice.
  ///
  /// In en, this message translates to:
  /// **'Override for this device'**
  String get overrideForDevice;

  /// No description provided for @addExtensionHint.
  ///
  /// In en, this message translates to:
  /// **'Add extension (e.g. tmp)'**
  String get addExtensionHint;

  /// No description provided for @addExtensionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add extension'**
  String get addExtensionTooltip;

  /// No description provided for @displayDeviceSection.
  ///
  /// In en, this message translates to:
  /// **'Display (this device)'**
  String get displayDeviceSection;

  /// No description provided for @resetToAppDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to app defaults'**
  String get resetToAppDefaults;

  /// No description provided for @displayFollowsDefaults.
  ///
  /// In en, this message translates to:
  /// **'These follow your app defaults unless you override them here.'**
  String get displayFollowsDefaults;

  /// No description provided for @sortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortLabel;

  /// No description provided for @backupRestoreSection.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get backupRestoreSection;

  /// No description provided for @exportConfig.
  ///
  /// In en, this message translates to:
  /// **'Export config'**
  String get exportConfig;

  /// No description provided for @importConfig.
  ///
  /// In en, this message translates to:
  /// **'Import config'**
  String get importConfig;

  /// No description provided for @importConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a previously exported file'**
  String get importConfigSubtitle;

  /// No description provided for @exportConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Export config'**
  String get exportConfigTitle;

  /// No description provided for @importConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Import config'**
  String get importConfigTitle;

  /// No description provided for @replaceCurrentConfig.
  ///
  /// In en, this message translates to:
  /// **'Replace current config?'**
  String get replaceCurrentConfig;

  /// No description provided for @passphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphraseLabel;

  /// No description provided for @confirmPassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm passphrase'**
  String get confirmPassphraseLabel;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @updatedToVersion.
  ///
  /// In en, this message translates to:
  /// **'Updated to v{version} ✓'**
  String updatedToVersion(String version);

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date (v{version})'**
  String upToDate(String version);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(String error);

  /// No description provided for @couldNotOpenInstaller.
  ///
  /// In en, this message translates to:
  /// **'Could not open the installer.'**
  String get couldNotOpenInstaller;

  /// No description provided for @updatingToVersion.
  ///
  /// In en, this message translates to:
  /// **'Updating to v{version}'**
  String updatingToVersion(String version);

  /// No description provided for @downloadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloadingStatus;

  /// No description provided for @downloadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%  ·  {received} / {totalSize}'**
  String downloadingProgress(String percent, String received, String totalSize);

  /// No description provided for @openingInstaller.
  ///
  /// In en, this message translates to:
  /// **'Opening installer…'**
  String get openingInstaller;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get somethingWentWrong;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available · v{version}'**
  String updateAvailable(String version);

  /// No description provided for @fmtMB.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String fmtMB(String value);

  /// No description provided for @fmtKB.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String fmtKB(String value);

  /// No description provided for @fmtBytes.
  ///
  /// In en, this message translates to:
  /// **'{value} B'**
  String fmtBytes(String value);

  /// No description provided for @clearCompletedButton.
  ///
  /// In en, this message translates to:
  /// **'Clear completed'**
  String get clearCompletedButton;

  /// No description provided for @noTransfers.
  ///
  /// In en, this message translates to:
  /// **'No transfers'**
  String get noTransfers;

  /// No description provided for @queuedStatus.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get queuedStatus;

  /// No description provided for @pauseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseTooltip;

  /// No description provided for @resumeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeTooltip;

  /// No description provided for @removedTransfer.
  ///
  /// In en, this message translates to:
  /// **'Removed {name}'**
  String removedTransfer(String name);

  /// No description provided for @transferProgress.
  ///
  /// In en, this message translates to:
  /// **'{transferred} / {total}'**
  String transferProgress(String transferred, String total);

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @uploadedStatus.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploadedStatus;

  /// No description provided for @downloadedStatus.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloadedStatus;

  /// No description provided for @savedToLocation.
  ///
  /// In en, this message translates to:
  /// **'Saved to {location}'**
  String savedToLocation(String location);

  /// No description provided for @sha256Prefix.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 {hash}…'**
  String sha256Prefix(String hash);

  /// No description provided for @transferringFile.
  ///
  /// In en, this message translates to:
  /// **'Transferring {name}'**
  String transferringFile(String name);

  /// No description provided for @transferringFileAndMore.
  ///
  /// In en, this message translates to:
  /// **'Transferring {name} (+{count} more)'**
  String transferringFileAndMore(String name, int count);

  /// No description provided for @loadingImage.
  ///
  /// In en, this message translates to:
  /// **'Loading image…'**
  String get loadingImage;

  /// No description provided for @couldNotLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Could not load image.\n{error}'**
  String couldNotLoadImage(String error);

  /// No description provided for @decodingImage.
  ///
  /// In en, this message translates to:
  /// **'Decoding image…'**
  String get decodingImage;

  /// No description provided for @couldNotDecodeImage.
  ///
  /// In en, this message translates to:
  /// **'Could not decode this image.\n{error}'**
  String couldNotDecodeImage(String error);

  /// No description provided for @loadingPdf.
  ///
  /// In en, this message translates to:
  /// **'Loading PDF…'**
  String get loadingPdf;

  /// No description provided for @couldNotLoadPdf.
  ///
  /// In en, this message translates to:
  /// **'Could not load this PDF.\n{error}'**
  String couldNotLoadPdf(String error);

  /// No description provided for @renderingPdf.
  ///
  /// In en, this message translates to:
  /// **'Rendering PDF…'**
  String get renderingPdf;

  /// No description provided for @couldNotRenderPdf.
  ///
  /// In en, this message translates to:
  /// **'Could not render this PDF.\n{error}'**
  String couldNotRenderPdf(String error);

  /// No description provided for @loadingText.
  ///
  /// In en, this message translates to:
  /// **'Loading text…'**
  String get loadingText;

  /// No description provided for @couldNotLoadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not load this file.\n{error}'**
  String couldNotLoadFile(String error);

  /// No description provided for @couldNotLoadVideo.
  ///
  /// In en, this message translates to:
  /// **'Could not load this video.\n{error}'**
  String couldNotLoadVideo(String error);

  /// No description provided for @couldNotLoadAudio.
  ///
  /// In en, this message translates to:
  /// **'Could not load this audio.\n{error}'**
  String couldNotLoadAudio(String error);

  /// No description provided for @connectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost — check your network and try again.'**
  String get connectionLost;

  /// No description provided for @couldNotLoadDrives.
  ///
  /// In en, this message translates to:
  /// **'Could not load drives: {error}'**
  String couldNotLoadDrives(String error);

  /// No description provided for @driveInfoFreeOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{free} free of {total}  ·  {path}'**
  String driveInfoFreeOfTotal(String free, String total, String path);

  /// No description provided for @alreadyInThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Already in this folder'**
  String get alreadyInThisFolder;

  /// No description provided for @clipboardAllExistNothing.
  ///
  /// In en, this message translates to:
  /// **'All clipboard items already exist in {folder} — nothing to {operation}'**
  String clipboardAllExistNothing(String folder, String operation);

  /// No description provided for @renamedLabel.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get renamedLabel;

  /// No description provided for @emptyFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get emptyFolderMessage;

  /// No description provided for @noMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'No items match the current filter'**
  String get noMatchesMessage;

  /// No description provided for @offlineBannerText.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached files'**
  String get offlineBannerText;

  /// No description provided for @defaultsApplyHint.
  ///
  /// In en, this message translates to:
  /// **'These defaults apply to every device. Override any of them for a single device from that device’s settings.'**
  String get defaultsApplyHint;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @wallpaperSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Material You — derive the palette from your wallpaper where supported'**
  String get wallpaperSubtitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @sortFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortFieldName;

  /// No description provided for @sortFieldSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortFieldSize;

  /// No description provided for @sortFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date modified'**
  String get sortFieldDate;

  /// No description provided for @sortFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortFieldType;

  /// No description provided for @invalidQrFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code format.'**
  String get invalidQrFormat;

  /// No description provided for @qrMissingFields.
  ///
  /// In en, this message translates to:
  /// **'QR missing required fields.'**
  String get qrMissingFields;

  /// No description provided for @sendViaQrButton.
  ///
  /// In en, this message translates to:
  /// **'Send via QR'**
  String get sendViaQrButton;

  /// No description provided for @qrHandoffSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan to receive'**
  String get qrHandoffSheetTitle;

  /// No description provided for @qrHandoffNoFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Can\'t share — this host has no pinned certificate.'**
  String get qrHandoffNoFingerprint;

  /// No description provided for @receiveFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Receive file'**
  String get receiveFileTooltip;

  /// No description provided for @receiveFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive file'**
  String get receiveFileTitle;

  /// No description provided for @qrHandoffNoHostMatch.
  ///
  /// In en, this message translates to:
  /// **'You\'re not paired to this PC — pair first, then scan again.'**
  String get qrHandoffNoHostMatch;

  /// No description provided for @backUpNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backUpNow;

  /// No description provided for @scanningStatus.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get scanningStatus;

  /// No description provided for @backingUpPhotos.
  ///
  /// In en, this message translates to:
  /// **'Backing up {count} photo(s)'**
  String backingUpPhotos(int count);

  /// No description provided for @alreadyUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get alreadyUpToDate;

  /// No description provided for @pickPcFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a PC and destination folder first'**
  String get pickPcFirst;

  /// No description provided for @photoAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Photo access denied — grant it in system settings'**
  String get photoAccessDenied;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @noPairedPcs.
  ///
  /// In en, this message translates to:
  /// **'No paired PCs — pair one first'**
  String get noPairedPcs;

  /// No description provided for @choosePc.
  ///
  /// In en, this message translates to:
  /// **'Choose a PC'**
  String get choosePc;

  /// No description provided for @backupRecordCleared.
  ///
  /// In en, this message translates to:
  /// **'Backup record cleared'**
  String get backupRecordCleared;

  /// No description provided for @resetBackupHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to forget the record (re-backs-up everything)'**
  String get resetBackupHint;

  /// No description provided for @destinationFolderHelper.
  ///
  /// In en, this message translates to:
  /// **'Photos land in <folder>/YYYY/YYYY-MM/'**
  String get destinationFolderHelper;

  /// No description provided for @preparingToShare.
  ///
  /// In en, this message translates to:
  /// **'Preparing {name} to share…'**
  String preparingToShare(String name);

  /// No description provided for @couldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Could not share {name}'**
  String couldNotShare(String name);

  /// No description provided for @openWithTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open with…'**
  String get openWithTooltip;

  /// No description provided for @openWithButton.
  ///
  /// In en, this message translates to:
  /// **'Open with…'**
  String get openWithButton;

  /// No description provided for @preparingToOpen.
  ///
  /// In en, this message translates to:
  /// **'Preparing {name}…'**
  String preparingToOpen(String name);

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {name}'**
  String couldNotOpen(String name);

  /// No description provided for @savingFile.
  ///
  /// In en, this message translates to:
  /// **'Saving {name}…'**
  String savingFile(String name);

  /// No description provided for @fileTooLargeToPreview.
  ///
  /// In en, this message translates to:
  /// **'This file is too large to preview ({sizeLabel}).\nDownload it to view it instead.'**
  String fileTooLargeToPreview(String sizeLabel);

  /// No description provided for @readOnlyModeSaveError.
  ///
  /// In en, this message translates to:
  /// **'This host is in read-only mode — changes can’t be saved.'**
  String get readOnlyModeSaveError;

  /// No description provided for @fileTooLargeToSave.
  ///
  /// In en, this message translates to:
  /// **'This file is too large to save.'**
  String get fileTooLargeToSave;

  /// No description provided for @staleWriteMessage.
  ///
  /// In en, this message translates to:
  /// **'This file was modified on the host since you opened it. You can reload the current version (your edits here will be lost) or overwrite it with your edits.'**
  String get staleWriteMessage;

  /// No description provided for @reloadedFromHost.
  ///
  /// In en, this message translates to:
  /// **'Reloaded the current version from the host'**
  String get reloadedFromHost;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @includeHiddenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Also show results hidden by file visibility settings'**
  String get includeHiddenSubtitle;

  /// No description provided for @writesRejected.
  ///
  /// In en, this message translates to:
  /// **'Writes are rejected'**
  String get writesRejected;

  /// No description provided for @phoneCanModify.
  ///
  /// In en, this message translates to:
  /// **'This phone can modify files'**
  String get phoneCanModify;

  /// No description provided for @allFoldersAllowed.
  ///
  /// In en, this message translates to:
  /// **'All folders allowed'**
  String get allFoldersAllowed;

  /// No description provided for @securityWarning.
  ///
  /// In en, this message translates to:
  /// **'This phone has full control of the host. Anyone with access to it can change these settings and reach allowed folders.'**
  String get securityWarning;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @revokedStatus.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get revokedStatus;

  /// No description provided for @activeStatus.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeStatus;

  /// No description provided for @limitedTo.
  ///
  /// In en, this message translates to:
  /// **'Limited to: {path}'**
  String limitedTo(String path);

  /// No description provided for @managedOnPc.
  ///
  /// In en, this message translates to:
  /// **'Managed on the PC'**
  String get managedOnPc;

  /// No description provided for @osLabel.
  ///
  /// In en, this message translates to:
  /// **'OS'**
  String get osLabel;

  /// No description provided for @driveCapacityLine.
  ///
  /// In en, this message translates to:
  /// **'Used {used} of {total} · {free} free'**
  String driveCapacityLine(String used, String total, String free);

  /// No description provided for @driveCapacityLineOs.
  ///
  /// In en, this message translates to:
  /// **'Used {used} of {total} · {free} free · contains the OS'**
  String driveCapacityLineOs(String used, String total, String free);

  /// No description provided for @addedFolder.
  ///
  /// In en, this message translates to:
  /// **'Added {path}'**
  String addedFolder(String path);

  /// No description provided for @removedFolder.
  ///
  /// In en, this message translates to:
  /// **'Removed {path}'**
  String removedFolder(String path);

  /// No description provided for @disconnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Disconnect failed: {error}'**
  String disconnectFailed(String error);

  /// No description provided for @disconnectDeviceMessage.
  ///
  /// In en, this message translates to:
  /// **'Disconnect this device from {pcName}? You’ll need a new pairing code to reconnect.'**
  String disconnectDeviceMessage(String pcName);

  /// No description provided for @noCustomExtensions.
  ///
  /// In en, this message translates to:
  /// **'None — add an extension below.'**
  String get noCustomExtensions;

  /// No description provided for @passphraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passphrases do not match'**
  String get passphraseMismatch;

  /// No description provided for @passphraseMinLength.
  ///
  /// In en, this message translates to:
  /// **'Passphrase must be at least 6 characters'**
  String get passphraseMinLength;

  /// No description provided for @usingDeviceVisibility.
  ///
  /// In en, this message translates to:
  /// **'Using device-specific visibility'**
  String get usingDeviceVisibility;

  /// No description provided for @usingAppDefault.
  ///
  /// In en, this message translates to:
  /// **'Using app default'**
  String get usingAppDefault;

  /// No description provided for @followsAppDefaultVisibility.
  ///
  /// In en, this message translates to:
  /// **'Follows your app-default file visibility unless you override it here.'**
  String get followsAppDefaultVisibility;

  /// No description provided for @overriddenForDevice.
  ///
  /// In en, this message translates to:
  /// **'Overridden for this device'**
  String get overriddenForDevice;

  /// No description provided for @usingAppDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Using app default ({label})'**
  String usingAppDefaultLabel(String label);

  /// No description provided for @checkingForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get checkingForUpdates;

  /// No description provided for @updateNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Update not completed — tap to retry.'**
  String get updateNotCompleted;

  /// No description provided for @openingInstallerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Opening installer — confirm in Android, then return here.'**
  String get openingInstallerConfirm;

  /// No description provided for @downloadPaused.
  ///
  /// In en, this message translates to:
  /// **'Download paused. Retry to resume where it left off.'**
  String get downloadPaused;

  /// No description provided for @exportConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save paired hosts, tokens, favorites, and settings to an encrypted file'**
  String get exportConfigSubtitle;

  /// No description provided for @backupEncryptionWarning.
  ///
  /// In en, this message translates to:
  /// **'Backups are encrypted with your passphrase. If you lose it, the backup cannot be recovered.'**
  String get backupEncryptionWarning;

  /// No description provided for @preparingBackup.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get preparingBackup;

  /// No description provided for @backupReadyToShare.
  ///
  /// In en, this message translates to:
  /// **'Backup ready to share'**
  String get backupReadyToShare;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file: {error}'**
  String couldNotReadFile(String error);

  /// No description provided for @importWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Importing replaces all current hosts, tokens, and settings on this device. Continue?'**
  String get importWarningMessage;

  /// No description provided for @restoringConfig.
  ///
  /// In en, this message translates to:
  /// **'Restoring config…'**
  String get restoringConfig;

  /// No description provided for @configRestored.
  ///
  /// In en, this message translates to:
  /// **'Config restored. For best results, fully close and reopen the app.'**
  String get configRestored;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @ascendingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascendingTooltip;

  /// No description provided for @descendingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descendingTooltip;

  /// No description provided for @pausedStatus.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pausedStatus;

  /// No description provided for @verifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verifiedLabel;

  /// No description provided for @metaPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get metaPath;

  /// No description provided for @metaSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get metaSize;

  /// No description provided for @metaType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get metaType;

  /// No description provided for @metaPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get metaPermissions;

  /// No description provided for @metaModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get metaModified;

  /// No description provided for @metaCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get metaCreated;

  /// No description provided for @metaSymlink.
  ///
  /// In en, this message translates to:
  /// **'Symlink'**
  String get metaSymlink;

  /// No description provided for @noLabel.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get noLabel;

  /// No description provided for @couldNotDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t duplicate \"{name}\"'**
  String couldNotDuplicate(String name);

  /// No description provided for @restoredItem.
  ///
  /// In en, this message translates to:
  /// **'Restored \"{name}\"'**
  String restoredItem(String name);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @deleteForeverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete \"{name}\"? This cannot be undone.'**
  String deleteForeverConfirm(String name);

  /// No description provided for @deletedForever.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\" forever'**
  String deletedForever(String name);

  /// No description provided for @emptyTrashBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all {count} item(s)? This cannot be undone.'**
  String emptyTrashBody(int count);

  /// No description provided for @trashEmptied.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied'**
  String get trashEmptied;

  /// No description provided for @emptyFailed.
  ///
  /// In en, this message translates to:
  /// **'Empty failed: {error}'**
  String emptyFailed(String error);

  /// No description provided for @trashIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashIsEmpty;

  /// No description provided for @trashEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deleted items appear here and can be restored.'**
  String get trashEmptySubtitle;

  /// No description provided for @deletedRelative.
  ///
  /// In en, this message translates to:
  /// **'deleted {relative}'**
  String deletedRelative(String relative);

  /// No description provided for @copyItemsTo.
  ///
  /// In en, this message translates to:
  /// **'Copy {count} {count, plural, =1{item} other{items}} to…'**
  String copyItemsTo(int count);

  /// No description provided for @moveItemsTo.
  ///
  /// In en, this message translates to:
  /// **'Move {count} {count, plural, =1{item} other{items}} to…'**
  String moveItemsTo(int count);

  /// No description provided for @copyHereButton.
  ///
  /// In en, this message translates to:
  /// **'Copy here'**
  String get copyHereButton;

  /// No description provided for @moveHereButton.
  ///
  /// In en, this message translates to:
  /// **'Move here'**
  String get moveHereButton;

  /// No description provided for @downloadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloadingEllipsis;

  /// No description provided for @transfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfersTitle;

  /// No description provided for @transferGroupActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get transferGroupActive;

  /// No description provided for @transferGroupQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get transferGroupQueued;

  /// No description provided for @transferGroupDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get transferGroupDone;

  /// No description provided for @transferGroupFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get transferGroupFailed;

  /// No description provided for @followsDefaultsOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'These follow your app defaults unless you override them here.'**
  String get followsDefaultsOverrideHint;

  /// No description provided for @importReplacesBody.
  ///
  /// In en, this message translates to:
  /// **'Importing replaces all current hosts, tokens, and settings on this device. Continue?'**
  String get importReplacesBody;

  /// No description provided for @searchCategoryFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get searchCategoryFolders;

  /// No description provided for @searchCategoryImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get searchCategoryImages;

  /// No description provided for @searchCategoryVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get searchCategoryVideos;

  /// No description provided for @searchCategoryAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get searchCategoryAudio;

  /// No description provided for @searchCategoryDocs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get searchCategoryDocs;

  /// No description provided for @searchCategoryArchives.
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get searchCategoryArchives;

  /// No description provided for @searchCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get searchCategoryOther;

  /// No description provided for @sizePresetAny.
  ///
  /// In en, this message translates to:
  /// **'Any size'**
  String get sizePresetAny;

  /// No description provided for @sizePresetMb1.
  ///
  /// In en, this message translates to:
  /// **'> 1 MB'**
  String get sizePresetMb1;

  /// No description provided for @sizePresetMb10.
  ///
  /// In en, this message translates to:
  /// **'> 10 MB'**
  String get sizePresetMb10;

  /// No description provided for @sizePresetMb100.
  ///
  /// In en, this message translates to:
  /// **'> 100 MB'**
  String get sizePresetMb100;

  /// No description provided for @sizePresetGb1.
  ///
  /// In en, this message translates to:
  /// **'> 1 GB'**
  String get sizePresetGb1;

  /// No description provided for @datePresetAny.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get datePresetAny;

  /// No description provided for @datePresetLast24h.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get datePresetLast24h;

  /// No description provided for @datePresetLast7d.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get datePresetLast7d;

  /// No description provided for @datePresetLast30d.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get datePresetLast30d;

  /// No description provided for @datePresetThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get datePresetThisYear;

  /// No description provided for @wakeButton.
  ///
  /// In en, this message translates to:
  /// **'Wake'**
  String get wakeButton;

  /// No description provided for @wolPacketSent.
  ///
  /// In en, this message translates to:
  /// **'Magic packet sent to {hostname}'**
  String wolPacketSent(String hostname);

  /// No description provided for @wolPacketFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send magic packet'**
  String get wolPacketFailed;

  /// No description provided for @previewPageIndicator.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String previewPageIndicator(int current, int total);

  /// No description provided for @bandwidthSection.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get bandwidthSection;

  /// No description provided for @bandwidthUploadLimit.
  ///
  /// In en, this message translates to:
  /// **'Upload limit'**
  String get bandwidthUploadLimit;

  /// No description provided for @bandwidthDownloadLimit.
  ///
  /// In en, this message translates to:
  /// **'Download limit'**
  String get bandwidthDownloadLimit;

  /// No description provided for @bandwidthUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get bandwidthUnlimited;

  /// No description provided for @cacheSection.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cacheSection;

  /// No description provided for @cacheListingLabel.
  ///
  /// In en, this message translates to:
  /// **'Listing cache'**
  String get cacheListingLabel;

  /// No description provided for @cacheTempLabel.
  ///
  /// In en, this message translates to:
  /// **'Downloaded files'**
  String get cacheTempLabel;

  /// No description provided for @cacheTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cacheTotalLabel;

  /// No description provided for @cacheClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all cache'**
  String get cacheClearAll;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get cacheCleared;

  /// No description provided for @cacheCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get cacheCalculating;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Remote File Explorer'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Browse, manage, and transfer files between your phone and any PC on your network.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get onboardingHowTitle;

  /// No description provided for @onboardingHowBody.
  ///
  /// In en, this message translates to:
  /// **'Install the agent on your PC, pair it with this app using a one-time code, and you\'re connected — over Wi-Fi or Tailscale.'**
  String get onboardingHowBody;

  /// No description provided for @onboardingReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to go'**
  String get onboardingReadyTitle;

  /// No description provided for @onboardingReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Pair your first PC to start exploring. Your files stay on your devices — nothing goes to the cloud.'**
  String get onboardingReadyBody;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @notificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsSection;

  /// No description provided for @transferNotifications.
  ///
  /// In en, this message translates to:
  /// **'Transfer notifications'**
  String get transferNotifications;

  /// No description provided for @transferNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a notification when transfers complete'**
  String get transferNotificationsSubtitle;

  /// No description provided for @lowDiskAlerts.
  ///
  /// In en, this message translates to:
  /// **'Low disk alerts'**
  String get lowDiskAlerts;

  /// No description provided for @lowDiskAlertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a warning when a drive has less than 1 GB free'**
  String get lowDiskAlertsSubtitle;

  /// No description provided for @lowDiskWarning.
  ///
  /// In en, this message translates to:
  /// **'Low disk space'**
  String get lowDiskWarning;

  /// No description provided for @wolRelayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not wake via relay'**
  String get wolRelayFailed;

  /// No description provided for @wolRelaySent.
  ///
  /// In en, this message translates to:
  /// **'Wake packet sent via {relayHost}'**
  String wolRelaySent(String relayHost);

  /// No description provided for @savedSearches.
  ///
  /// In en, this message translates to:
  /// **'Saved searches'**
  String get savedSearches;

  /// No description provided for @saveSearch.
  ///
  /// In en, this message translates to:
  /// **'Save search'**
  String get saveSearch;

  /// No description provided for @savedSearchName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get savedSearchName;

  /// No description provided for @noSavedSearches.
  ///
  /// In en, this message translates to:
  /// **'No saved searches yet'**
  String get noSavedSearches;

  /// No description provided for @deleteSavedSearch.
  ///
  /// In en, this message translates to:
  /// **'Delete saved search'**
  String get deleteSavedSearch;

  /// No description provided for @searchModeSubstring.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get searchModeSubstring;

  /// No description provided for @searchModeGlob.
  ///
  /// In en, this message translates to:
  /// **'Glob'**
  String get searchModeGlob;

  /// No description provided for @searchModeRegex.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get searchModeRegex;

  /// No description provided for @diagnosticsExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsExportTitle;

  /// No description provided for @diagnosticsExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics'**
  String get diagnosticsExportButton;

  /// No description provided for @diagnosticsExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share device and connection info for troubleshooting'**
  String get diagnosticsExportSubtitle;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard'**
  String get diagnosticsCopied;

  /// No description provided for @audioSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get audioSpeedLabel;

  /// No description provided for @audioSpeedValue.
  ///
  /// In en, this message translates to:
  /// **'{speed}x'**
  String audioSpeedValue(String speed);

  /// No description provided for @audioDownloadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio for preview… {percent}%'**
  String audioDownloadingProgress(String percent);

  /// No description provided for @storageByTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage by type'**
  String get storageByTypeTitle;

  /// No description provided for @sseConnected.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get sseConnected;

  /// No description provided for @chmodTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get chmodTitle;

  /// No description provided for @chmodOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get chmodOwner;

  /// No description provided for @chmodGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get chmodGroup;

  /// No description provided for @chmodOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get chmodOther;

  /// No description provided for @discoveredHosts.
  ///
  /// In en, this message translates to:
  /// **'Discovered on network'**
  String get discoveredHosts;

  /// No description provided for @archiveContents.
  ///
  /// In en, this message translates to:
  /// **'Archive Contents'**
  String get archiveContents;

  /// No description provided for @archiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty archive'**
  String get archiveEmpty;

  /// No description provided for @archiveEntries.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String archiveEntries(int count);

  /// No description provided for @dupFinderTitle.
  ///
  /// In en, this message translates to:
  /// **'Find Duplicates'**
  String get dupFinderTitle;

  /// No description provided for @dupFinderScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Finder'**
  String get dupFinderScreenTitle;

  /// No description provided for @dupFinderScan.
  ///
  /// In en, this message translates to:
  /// **'Scan for Duplicates'**
  String get dupFinderScan;

  /// No description provided for @dupFinderScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning {count} files...'**
  String dupFinderScanning(int count);

  /// No description provided for @dupFinderNone.
  ///
  /// In en, this message translates to:
  /// **'No duplicates found'**
  String get dupFinderNone;

  /// No description provided for @syncRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync Rules'**
  String get syncRulesTitle;

  /// No description provided for @syncRulesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download remote folders to local storage'**
  String get syncRulesSubtitle;

  /// No description provided for @syncAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add Sync Rule'**
  String get syncAddRule;

  /// No description provided for @syncDeleteRule.
  ///
  /// In en, this message translates to:
  /// **'Delete Sync Rule'**
  String get syncDeleteRule;

  /// No description provided for @syncDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this sync rule?'**
  String get syncDeleteConfirm;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// No description provided for @syncNever.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncNever;

  /// No description provided for @syncNoRules.
  ///
  /// In en, this message translates to:
  /// **'No sync rules yet'**
  String get syncNoRules;

  /// No description provided for @syncRemotePath.
  ///
  /// In en, this message translates to:
  /// **'Remote Path'**
  String get syncRemotePath;

  /// No description provided for @syncLocalPath.
  ///
  /// In en, this message translates to:
  /// **'Local Folder'**
  String get syncLocalPath;

  /// No description provided for @crossHostSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search All Hosts'**
  String get crossHostSearchTitle;

  /// No description provided for @crossHostSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search all hosts...'**
  String get crossHostSearchHint;

  /// No description provided for @crossHostSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching {count} hosts...'**
  String crossHostSearching(int count);

  /// No description provided for @crossHostNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get crossHostNoResults;

  /// No description provided for @crossHostTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search across all hosts'**
  String get crossHostTypeToSearch;

  /// No description provided for @crossHostSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search all hosts'**
  String get crossHostSearchTooltip;

  /// No description provided for @commandPaletteTitle.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get commandPaletteTitle;

  /// No description provided for @commandPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Type a command...'**
  String get commandPaletteHint;

  /// No description provided for @goToPathTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to Path'**
  String get goToPathTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
