// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مستكشف الملفات';

  @override
  String get browseButton => 'تصفّح';

  @override
  String get searchButton => 'بحث';

  @override
  String get moreTooltip => 'المزيد';

  @override
  String get refreshTooltip => 'تحديث';

  @override
  String get appSettingsTooltip => 'إعدادات التطبيق';

  @override
  String get cancelButton => 'إلغاء';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get okButton => 'حسناً';

  @override
  String get saveButton => 'حفظ';

  @override
  String get closeButton => 'إغلاق';

  @override
  String get addButton => 'إضافة';

  @override
  String get createButton => 'إنشاء';

  @override
  String get applyButton => 'تطبيق';

  @override
  String get resetButton => 'إعادة تعيين';

  @override
  String get updateButton => 'تحديث';

  @override
  String get dismissButton => 'تجاهل';

  @override
  String get undoButton => 'تراجع';

  @override
  String get continueButton => 'متابعة';

  @override
  String get replaceButton => 'استبدال';

  @override
  String get discardButton => 'تجاهل';

  @override
  String get pairButton => 'إقران';

  @override
  String get onlineStatus => 'متصل';

  @override
  String get offlineStatus => 'غير متصل';

  @override
  String get checkingStatus => 'جارٍ الفحص…';

  @override
  String get networkLan => 'شبكة محلية';

  @override
  String get networkTailscale => 'Tailscale';

  @override
  String hostSubtitleVersionNetwork(String version, String network) {
    return 'v$version · $network';
  }

  @override
  String statusCheckedRelative(String relative) {
    return 'فُحص $relative';
  }

  @override
  String statusOfflineLastSeen(String relative) {
    return 'غير متصل · آخر ظهور $relative';
  }

  @override
  String get relativeJustNow => 'الآن';

  @override
  String relativeSecondsAgo(int count) {
    return 'منذ $count ث';
  }

  @override
  String relativeMinutesAgo(int count) {
    return 'منذ $count د';
  }

  @override
  String relativeHoursAgo(int count) {
    return 'منذ $count س';
  }

  @override
  String relativeDaysAgo(int count) {
    return 'منذ $count ي';
  }

  @override
  String get couldNotReachComputer => 'تعذّر الاتصال بهذا الحاسوب.';

  @override
  String get forgetComputerTitle => 'إزالة هذا الحاسوب؟';

  @override
  String forgetComputerConfirm(String hostLabel) {
    return 'إزالة \"$hostLabel\"؟ يمكنك إضافته لاحقاً.';
  }

  @override
  String get forgetButton => 'إزالة';

  @override
  String get forgetComputerMenuItem => 'إزالة هذا الحاسوب';

  @override
  String get storageMenuItem => 'التخزين';

  @override
  String get transfersMenuItem => 'عمليات النقل';

  @override
  String get diagnosticsMenuItem => 'التشخيص';

  @override
  String get settingsMenuItem => 'الإعدادات';

  @override
  String nMoreDrives(int count) {
    return '+$count أقراص أخرى';
  }

  @override
  String get addComputerButton => 'إضافة حاسوب';

  @override
  String get scanQrCodeButton => 'مسح رمز QR';

  @override
  String get emptyStatePairTitle => 'اقترن بأول حاسوب';

  @override
  String get emptyStatePairBody =>
      'امسح رمز QR الذي يعرضه وكيل سطح المكتب لتوصيل هذا الهاتف عبر شبكتك أو Tailscale.';

  @override
  String errorLabel(String error) {
    return 'خطأ: $error';
  }

  @override
  String get connectionDiagnosticsTitle => 'تشخيص الاتصال';

  @override
  String get retestButton => 'إعادة الفحص';

  @override
  String get probeTimedOut => 'انتهت المهلة';

  @override
  String get probeError => 'خطأ';

  @override
  String probeLatencyMs(int ms) {
    return '$ms مللي ثانية';
  }

  @override
  String hostStorageTitle(String hostLabel) {
    return '$hostLabel · التخزين';
  }

  @override
  String get allDrives => 'جميع الأقراص';

  @override
  String couldNotLoadStorage(String error) {
    return 'تعذّر تحميل التخزين: $error';
  }

  @override
  String freeOfTotal(String free, String total) {
    return '$free متاح من $total';
  }

  @override
  String freeOfTotalDrives(String free, String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قرص',
      few: '$count أقراص',
      two: 'قرصان',
      one: 'قرص واحد',
    );
    return '$free متاح من $total · $_temp0';
  }

  @override
  String get searchHint => 'ابحث عن ملفات ومجلدات…';

  @override
  String get clearTooltip => 'مسح';

  @override
  String get searchFiltersTooltip => 'فلاتر البحث';

  @override
  String activeFilterCount(int count) {
    return '$count';
  }

  @override
  String get globPattern => 'نمط Glob';

  @override
  String get clearAllButton => 'مسح الكل';

  @override
  String get removeTooltip => 'إزالة';

  @override
  String get fileSize => 'حجم الملف';

  @override
  String get searchScope => 'نطاق البحث';

  @override
  String get fromHere => 'من هنا';

  @override
  String get everywhere => 'في كل مكان';

  @override
  String get includeHiddenItems => 'تضمين العناصر المخفية';

  @override
  String searchFailed(String error) {
    return 'فشل البحث: $error';
  }

  @override
  String noResultsFor(String query) {
    return 'لا نتائج لـ \"$query\".';
  }

  @override
  String get typeToSearch => 'اكتب للبحث عن ملفات ومجلدات بالاسم.';

  @override
  String showingFirstNResults(int limit) {
    return 'عرض أول $limit نتيجة — حسّن بحثك.';
  }

  @override
  String get searchTimedOut => 'انتهت مهلة البحث — عرض نتائج جزئية.';

  @override
  String searchingIn(String path) {
    return 'البحث في: $path';
  }

  @override
  String get searchingEverywhere => 'البحث في كل مكان';

  @override
  String get searchTooltip => 'بحث';

  @override
  String get clearSelectionTooltip => 'إلغاء التحديد';

  @override
  String get batchRenameTooltip => 'إعادة تسمية جماعية';

  @override
  String get invertSelectionTooltip => 'عكس التحديد';

  @override
  String get selectAllTooltip => 'تحديد الكل';

  @override
  String get deselectAllTooltip => 'إلغاء تحديد الكل';

  @override
  String nSelected(int count) {
    return '$count محدد';
  }

  @override
  String get uploadFileTooltip => 'رفع ملف';

  @override
  String get newButton => 'جديد';

  @override
  String get favoriteFolderTooltip => 'إضافة إلى المفضلة';

  @override
  String get removeFavoriteTooltip => 'إزالة من المفضلة';

  @override
  String get viewOptionsTitle => 'خيارات العرض';

  @override
  String get layoutLabel => 'التخطيط';

  @override
  String get listLabel => 'قائمة';

  @override
  String get gridLabel => 'شبكة';

  @override
  String get densityLabel => 'الكثافة';

  @override
  String get comfortableLabel => 'مريح';

  @override
  String get compactLabel => 'مضغوط';

  @override
  String get sortByLabel => 'ترتيب حسب';

  @override
  String get showHiddenItems => 'إظهار العناصر المخفية';

  @override
  String nHiddenByVisibility(int count) {
    return '$count مخفي بواسطة إعدادات إظهار الملفات';
  }

  @override
  String get newFolderButton => 'مجلد جديد';

  @override
  String get newFileButton => 'ملف جديد';

  @override
  String get nameHint => 'الاسم';

  @override
  String createdName(String name) {
    return 'أُنشئ $name';
  }

  @override
  String createFailed(String name, String error) {
    return 'تعذّر إنشاء $name: $error';
  }

  @override
  String get favoritesTitle => 'المفضلة';

  @override
  String get noFavoritesYet =>
      'لا مفضلات بعد. افتح مجلداً والمس النجمة لإضافته.';

  @override
  String get cancelTooltip => 'إلغاء';

  @override
  String get nameConflictTitle => 'تعارض في الاسم';

  @override
  String nameConflictBody(int collidingCount, int totalCount, String dest) {
    return '$collidingCount من $totalCount عنصر موجود بالفعل في $dest.';
  }

  @override
  String get skipTheseButton => 'تخطي هذه';

  @override
  String get keepBothButton => 'الاحتفاظ بالاثنين';

  @override
  String get overwriteButton => 'استبدال';

  @override
  String get previewButton => 'معاينة';

  @override
  String get downloadButton => 'تنزيل';

  @override
  String get extractHereButton => 'استخراج هنا';

  @override
  String get renameButton => 'إعادة تسمية';

  @override
  String get duplicateButton => 'نسخ مكرر';

  @override
  String get deleteButton => 'حذف';

  @override
  String get newNameLabel => 'الاسم الجديد';

  @override
  String get deleteTitle => 'حذف؟';

  @override
  String get deleteForeverButton => 'حذف نهائي';

  @override
  String get moveToTrashButton => 'نقل إلى سلة المهملات';

  @override
  String get favoriteButton => 'إضافة للمفضلة';

  @override
  String get unfavoriteButton => 'إزالة من المفضلة';

  @override
  String get yesLabel => 'نعم';

  @override
  String copiedPath(String path) {
    return 'نُسخ \"$path\"';
  }

  @override
  String removedFavorite(String name) {
    return 'أُزيل \"$name\" من المفضلة';
  }

  @override
  String addedFavorite(String name) {
    return 'أُضيف \"$name\" إلى المفضلة';
  }

  @override
  String downloadingFile(String name) {
    return 'جارٍ تنزيل $name…';
  }

  @override
  String renamedTo(String newName) {
    return 'أُعيدت التسمية إلى $newName';
  }

  @override
  String renameFailed(String error) {
    return 'فشلت إعادة التسمية: $error';
  }

  @override
  String duplicatedFile(String name) {
    return 'نُسخ \"$name\"';
  }

  @override
  String duplicateFailed(String error) {
    return 'فشل النسخ المكرر: $error';
  }

  @override
  String extractedFile(String name) {
    return 'استُخرج \"$name\"';
  }

  @override
  String extractFailed(String error) {
    return 'فشل الاستخراج: $error';
  }

  @override
  String moveToTrashConfirm(String name) {
    return 'نقل \"$name\" إلى سلة المهملات؟ يمكنك استعادته لاحقاً.';
  }

  @override
  String deletedName(String name) {
    return 'حُذف $name';
  }

  @override
  String movedToTrashName(String name) {
    return 'نُقل $name إلى سلة المهملات';
  }

  @override
  String deleteFailed(String error) {
    return 'فشل الحذف: $error';
  }

  @override
  String get folderDetailsTooltip => 'تفاصيل المجلد';

  @override
  String get trashTitle => 'سلة المهملات';

  @override
  String get emptyTrashTooltip => 'إفراغ سلة المهملات';

  @override
  String get deleteForeverTitle => 'حذف نهائي؟';

  @override
  String get emptyTrashTitle => 'إفراغ سلة المهملات؟';

  @override
  String get restoreButton => 'استعادة';

  @override
  String get patternLabel => 'نمط';

  @override
  String get findAndReplaceLabel => 'بحث واستبدال';

  @override
  String get baseNameLabel => 'الاسم الأساسي';

  @override
  String get startNumberLabel => 'رقم البداية';

  @override
  String get findLabel => 'بحث';

  @override
  String get replaceWithLabel => 'استبدال بـ';

  @override
  String renameNItemsTitle(int count) {
    return 'إعادة تسمية $count عنصر';
  }

  @override
  String renameNItems(int count) {
    return 'إعادة تسمية $count';
  }

  @override
  String get baseNameHelperText => 'ضع الرقم برمز n؛ وإلا يُضاف في النهاية.';

  @override
  String andNMore(int count) {
    return '… و$count أخرى';
  }

  @override
  String batchSuccessNItems(String verb, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
    );
    return '$verb $_temp0';
  }

  @override
  String batchResultWithErrors(String verb, int errorCount) {
    return '$verb مع $errorCount خطأ';
  }

  @override
  String get cutButton => 'قص';

  @override
  String get copyButton => 'نسخ';

  @override
  String get compressButton => 'ضغط';

  @override
  String moveNItemsToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
    );
    return 'نقل $_temp0 إلى سلة المهملات؟';
  }

  @override
  String canRestoreFromTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'هذه العناصر',
      one: 'هذا العنصر',
    );
    return 'يمكنك استعادة $_temp0 من سلة المهملات.';
  }

  @override
  String compressedTo(String name) {
    return 'ضُغط إلى $name';
  }

  @override
  String compressFailed(String error) {
    return 'فشل الضغط: $error';
  }

  @override
  String queuedNDownloads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تنزيل',
      few: '$count تنزيلات',
      two: 'تنزيلان',
      one: 'تنزيل واحد',
    );
    return '$_temp0 في قائمة الانتظار';
  }

  @override
  String get deletedLabel => 'حُذف';

  @override
  String get movedToTrashLabel => 'نُقل إلى سلة المهملات';

  @override
  String clipboardCopiedHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر نُسخ',
      few: '$count عناصر نُسخت',
      two: 'عنصران نُسخا',
      one: 'عنصر واحد نُسخ',
    );
    return '$_temp0 — افتح مجلداً والمس لصق';
  }

  @override
  String clipboardCutHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر قُصّ',
      few: '$count عناصر قُصّت',
      two: 'عنصران قُصّا',
      one: 'عنصر واحد قُص',
    );
    return '$_temp0 — افتح مجلداً والمس لصق';
  }

  @override
  String pasteNItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
    );
    return 'لصق $_temp0';
  }

  @override
  String get movedLabel => 'نُقل';

  @override
  String get copiedLabel => 'نُسخ';

  @override
  String get moveLabel => 'نقل';

  @override
  String get copyLabel => 'نسخ';

  @override
  String operationFailed(String operation, String error) {
    return 'فشلت عملية $operation: $error';
  }

  @override
  String alreadyExistsSkipped(String name) {
    return '$name موجود بالفعل — تم التخطي';
  }

  @override
  String uploadingFile(String name) {
    return 'جارٍ رفع $name…';
  }

  @override
  String nHidden(int count) {
    return '$count مخفي';
  }

  @override
  String get hideLabel => 'إخفاء';

  @override
  String get showLabel => 'إظهار';

  @override
  String itemExistsInFolder(String name, String folder) {
    return '$name موجود بالفعل في $folder';
  }

  @override
  String couldNotCheckFolder(String folder, String error) {
    return 'تعذّر فحص $folder للعناصر الموجودة: $error';
  }

  @override
  String movedFile(String name) {
    return 'نُقل $name';
  }

  @override
  String moveFailed(String error) {
    return 'فشل النقل: $error';
  }

  @override
  String nothingToPaste(String folder, String operation) {
    return '$folder — لا شيء لـ$operation';
  }

  @override
  String pathLabel(String label) {
    return '$label · ';
  }

  @override
  String get showHiddenFoldersTooltip => 'إظهار المجلدات المخفية';

  @override
  String get addComputerTitle => 'إضافة حاسوب';

  @override
  String get scanQrTab => 'مسح QR';

  @override
  String get manualTab => 'يدوي';

  @override
  String get agentAddressLabel => 'عنوان الوكيل';

  @override
  String get agentAddressHint => '192.168.1.10:8765';

  @override
  String get pairingCodeLabel => 'رمز الإقران';

  @override
  String get pairingCodeHint => '123456';

  @override
  String get requiredLabel => 'مطلوب';

  @override
  String pairedWith(String name) {
    return 'تم الإقران مع $name';
  }

  @override
  String fingerprintMismatch(String error) {
    return 'عدم تطابق البصمة: $error';
  }

  @override
  String pairingFailed(String error) {
    return 'فشل الإقران: $error';
  }

  @override
  String get photoBackupTitle => 'نسخ الصور احتياطياً';

  @override
  String get enablePhotoBackup => 'تفعيل نسخ الصور احتياطياً';

  @override
  String get photoBackupSubtitle => 'اتجاه واحد: نسخ الصور الجديدة إلى حاسوبك';

  @override
  String get backUpTo => 'نسخ إلى';

  @override
  String get destinationFolderLabel => 'مجلد الوجهة على الحاسوب';

  @override
  String get destinationFolderHint => '/home/you/PhoneBackup';

  @override
  String get onlyOnWifi => 'عبر Wi-Fi فقط';

  @override
  String get onlyWhileCharging => 'أثناء الشحن فقط';

  @override
  String photosBackedUp(int count) {
    return 'تم نسخ $count صورة احتياطياً';
  }

  @override
  String get shareTooltip => 'مشاركة';

  @override
  String get saveToDeviceTooltip => 'حفظ على الجهاز';

  @override
  String get showInFolderTooltip => 'عرض في المجلد';

  @override
  String get deleteTooltip => 'حذف';

  @override
  String get fileChangedOnDisk => 'تغيّر الملف على القرص';

  @override
  String get reloadButton => 'إعادة تحميل';

  @override
  String get discardChangesTitle => 'تجاهل التعديلات؟';

  @override
  String get unsavedChangesMessage => 'لديك تعديلات غير محفوظة ستُفقد.';

  @override
  String get keepEditingButton => 'متابعة التحرير';

  @override
  String get saveTooltip => 'حفظ';

  @override
  String savedFile(String name) {
    return 'حُفظ \"$name\"';
  }

  @override
  String couldNotSaveFile(String error) {
    return 'تعذّر حفظ هذا الملف.\n$error';
  }

  @override
  String couldNotReloadFile(String error) {
    return 'تعذّر إعادة تحميل هذا الملف.\n$error';
  }

  @override
  String get editTooltip => 'تحرير';

  @override
  String get hideLineNumbers => 'إخفاء أرقام الأسطر';

  @override
  String get appSettingsTitle => 'إعدادات التطبيق';

  @override
  String get appearanceSection => 'المظهر';

  @override
  String get systemTheme => 'النظام';

  @override
  String get lightTheme => 'فاتح';

  @override
  String get darkTheme => 'داكن';

  @override
  String get useWallpaperColors => 'استخدام ألوان الخلفية';

  @override
  String get displaySection => 'العرض';

  @override
  String get updatesSection => 'التحديثات';

  @override
  String get photoBackupSection => 'نسخ الصور';

  @override
  String get copyPhonePhotos => 'نسخ صور الهاتف إلى الحاسوب';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get agentSection => 'الوكيل';

  @override
  String get agentNameLabel => 'اسم الوكيل';

  @override
  String get accessSection => 'الوصول';

  @override
  String get readOnlyMode => 'وضع القراءة فقط';

  @override
  String get allowedFoldersSection => 'المجلدات المسموحة';

  @override
  String get addFolderTooltip => 'إضافة مجلد';

  @override
  String get removeFolderTooltip => 'إزالة مجلد';

  @override
  String get pairedDevicesSection => 'الأجهزة المقترنة';

  @override
  String get aboutSection => 'حول';

  @override
  String get pcNameLabel => 'اسم الحاسوب';

  @override
  String get disconnectButton => 'قطع الاتصال';

  @override
  String get disconnectDeviceTitle => 'قطع الاتصال بهذا الجهاز؟';

  @override
  String get addAllowedFolder => 'إضافة مجلد مسموح';

  @override
  String get allowedFolderHint => '/home/me/Documents';

  @override
  String get renameAgentTitle => 'إعادة تسمية الوكيل';

  @override
  String get hideDotfiles => 'إخفاء ملفات النقطة';

  @override
  String get hideDotfilesSubtitle =>
      'إخفاء الملفات والمجلدات التي تبدأ بـ \".\"';

  @override
  String get customLabel => 'مخصص';

  @override
  String dotExtension(String ext) {
    return '.$ext';
  }

  @override
  String get fileVisibilitySection => 'إظهار الملفات';

  @override
  String get fileVisibilityDeviceSection => 'إظهار الملفات (هذا الجهاز)';

  @override
  String get overrideForDevice => 'تخصيص لهذا الجهاز';

  @override
  String get addExtensionHint => 'إضافة امتداد (مثل tmp)';

  @override
  String get addExtensionTooltip => 'إضافة امتداد';

  @override
  String get displayDeviceSection => 'العرض (هذا الجهاز)';

  @override
  String get resetToAppDefaults => 'إعادة تعيين للإعدادات الافتراضية';

  @override
  String get displayFollowsDefaults =>
      'تتبع الإعدادات الافتراضية للتطبيق ما لم تقم بتخصيصها هنا.';

  @override
  String get sortLabel => 'الترتيب';

  @override
  String get backupRestoreSection => 'النسخ الاحتياطي والاستعادة';

  @override
  String get exportConfig => 'تصدير الإعدادات';

  @override
  String get importConfig => 'استيراد الإعدادات';

  @override
  String get importConfigSubtitle => 'الاستعادة من ملف مُصدَّر سابقاً';

  @override
  String get exportConfigTitle => 'تصدير الإعدادات';

  @override
  String get importConfigTitle => 'استيراد الإعدادات';

  @override
  String get replaceCurrentConfig => 'استبدال الإعدادات الحالية؟';

  @override
  String get passphraseLabel => 'كلمة المرور';

  @override
  String get confirmPassphraseLabel => 'تأكيد كلمة المرور';

  @override
  String get checkForUpdates => 'التحقق من التحديثات';

  @override
  String updatedToVersion(String version) {
    return 'تم التحديث إلى v$version ✓';
  }

  @override
  String upToDate(String version) {
    return 'محدّث (v$version)';
  }

  @override
  String updateFailed(String error) {
    return 'فشل التحديث: $error';
  }

  @override
  String get couldNotOpenInstaller => 'تعذّر فتح المثبّت.';

  @override
  String updatingToVersion(String version) {
    return 'جارٍ التحديث إلى v$version';
  }

  @override
  String get downloadingStatus => 'جارٍ التنزيل…';

  @override
  String downloadingProgress(
    String percent,
    String received,
    String totalSize,
  ) {
    return 'جارٍ التنزيل $percent%  ·  $received / $totalSize';
  }

  @override
  String get openingInstaller => 'جارٍ فتح المثبّت…';

  @override
  String get somethingWentWrong => 'حدث خطأ ما.';

  @override
  String updateAvailable(String version) {
    return 'تحديث متاح · v$version';
  }

  @override
  String fmtMB(String value) {
    return '$value م.ب';
  }

  @override
  String fmtKB(String value) {
    return '$value ك.ب';
  }

  @override
  String fmtBytes(String value) {
    return '$value بايت';
  }

  @override
  String get clearCompletedButton => 'مسح المكتملة';

  @override
  String get noTransfers => 'لا توجد عمليات نقل';

  @override
  String get queuedStatus => 'في الانتظار';

  @override
  String get pauseTooltip => 'إيقاف مؤقت';

  @override
  String get resumeTooltip => 'استئناف';

  @override
  String removedTransfer(String name) {
    return 'أُزيل $name';
  }

  @override
  String transferProgress(String transferred, String total) {
    return '$transferred / $total';
  }

  @override
  String get unknownError => 'خطأ غير معروف';

  @override
  String get uploadedStatus => 'تم الرفع';

  @override
  String get downloadedStatus => 'تم التنزيل';

  @override
  String savedToLocation(String location) {
    return 'حُفظ في $location';
  }

  @override
  String sha256Prefix(String hash) {
    return 'SHA-256 $hash…';
  }

  @override
  String transferringFile(String name) {
    return 'جارٍ نقل $name';
  }

  @override
  String transferringFileAndMore(String name, int count) {
    return 'جارٍ نقل $name (+$count أخرى)';
  }

  @override
  String get loadingImage => 'جارٍ تحميل الصورة…';

  @override
  String couldNotLoadImage(String error) {
    return 'تعذّر تحميل الصورة.\n$error';
  }

  @override
  String get decodingImage => 'جارٍ فك ترميز الصورة…';

  @override
  String couldNotDecodeImage(String error) {
    return 'تعذّر فك ترميز هذه الصورة.\n$error';
  }

  @override
  String get loadingPdf => 'جارٍ تحميل PDF…';

  @override
  String couldNotLoadPdf(String error) {
    return 'تعذّر تحميل ملف PDF.\n$error';
  }

  @override
  String get renderingPdf => 'جارٍ عرض PDF…';

  @override
  String couldNotRenderPdf(String error) {
    return 'تعذّر عرض ملف PDF.\n$error';
  }

  @override
  String get loadingText => 'جارٍ تحميل النص…';

  @override
  String couldNotLoadFile(String error) {
    return 'تعذّر تحميل هذا الملف.\n$error';
  }

  @override
  String couldNotLoadVideo(String error) {
    return 'تعذّر تحميل هذا الفيديو.\n$error';
  }

  @override
  String couldNotLoadAudio(String error) {
    return 'تعذّر تحميل هذا الصوت.\n$error';
  }

  @override
  String get connectionLost => 'انقطع الاتصال — تحقق من شبكتك وأعد المحاولة.';

  @override
  String couldNotLoadDrives(String error) {
    return 'تعذّر تحميل الأقراص: $error';
  }

  @override
  String driveInfoFreeOfTotal(String free, String total, String path) {
    return '$free متاح من $total  ·  $path';
  }

  @override
  String get alreadyInThisFolder => 'موجود بالفعل في هذا المجلد';

  @override
  String clipboardAllExistNothing(String folder, String operation) {
    return 'جميع عناصر الحافظة موجودة بالفعل في $folder — لا شيء لـ$operation';
  }

  @override
  String get renamedLabel => 'أُعيدت التسمية';

  @override
  String get emptyFolderMessage => 'هذا المجلد فارغ';

  @override
  String get offlineBannerText => 'غير متصل — عرض الملفات المخزنة مؤقتاً';

  @override
  String get defaultsApplyHint =>
      'تُطبَّق هذه الإعدادات الافتراضية على كل جهاز. يمكنك تجاوز أيٍّ منها لجهاز معيّن من إعدادات ذلك الجهاز.';

  @override
  String get themeLabel => 'المظهر';

  @override
  String get wallpaperSubtitle =>
      'Material You — اشتق لوحة الألوان من خلفية شاشتك حيثما أمكن';

  @override
  String get languageLabel => 'اللغة';

  @override
  String get sortFieldName => 'الاسم';

  @override
  String get sortFieldSize => 'الحجم';

  @override
  String get sortFieldDate => 'تاريخ التعديل';

  @override
  String get sortFieldType => 'النوع';

  @override
  String get invalidQrFormat => 'تنسيق رمز QR غير صالح.';

  @override
  String get qrMissingFields => 'رمز QR يفتقر لحقول مطلوبة.';

  @override
  String get backUpNow => 'نسخ احتياطي الآن';

  @override
  String get scanningStatus => 'جارٍ الفحص…';

  @override
  String backingUpPhotos(int count) {
    return 'جارٍ النسخ الاحتياطي لـ$count صورة';
  }

  @override
  String get alreadyUpToDate => 'محدّث بالفعل';

  @override
  String get pickPcFirst => 'اختر حاسوباً ومجلد وجهة أولاً';

  @override
  String get photoAccessDenied =>
      'تم رفض الوصول للصور — امنح الإذن من إعدادات النظام';

  @override
  String backupFailed(String error) {
    return 'فشل النسخ الاحتياطي: $error';
  }

  @override
  String get noPairedPcs => 'لا توجد حواسيب مقترنة — اقرن واحداً أولاً';

  @override
  String get choosePc => 'اختر حاسوباً';

  @override
  String get backupRecordCleared => 'تم مسح سجل النسخ الاحتياطي';

  @override
  String get resetBackupHint => 'انقر لنسيان السجل (يعيد نسخ كل شيء احتياطياً)';

  @override
  String get destinationFolderHelper => 'تُحفظ الصور في <مجلد>/YYYY/YYYY-MM/';

  @override
  String preparingToShare(String name) {
    return 'جارٍ تجهيز $name للمشاركة…';
  }

  @override
  String couldNotShare(String name) {
    return 'تعذّرت مشاركة $name';
  }

  @override
  String get openWithTooltip => 'فتح بواسطة…';

  @override
  String get openWithButton => 'فتح بواسطة…';

  @override
  String preparingToOpen(String name) {
    return 'جارٍ تجهيز $name…';
  }

  @override
  String couldNotOpen(String name) {
    return 'تعذّر فتح $name';
  }

  @override
  String savingFile(String name) {
    return 'جارٍ حفظ $name…';
  }

  @override
  String fileTooLargeToPreview(String sizeLabel) {
    return 'هذا الملف كبير جداً للمعاينة ($sizeLabel).\nحمّله لعرضه بدلاً من ذلك.';
  }

  @override
  String get readOnlyModeSaveError =>
      'هذا المضيف في وضع القراءة فقط — لا يمكن حفظ التغييرات.';

  @override
  String get fileTooLargeToSave => 'هذا الملف كبير جداً للحفظ.';

  @override
  String get staleWriteMessage =>
      'تم تعديل هذا الملف على المضيف منذ فتحته. يمكنك إعادة تحميل النسخة الحالية (ستُفقد تعديلاتك هنا) أو الكتابة فوقها بتعديلاتك.';

  @override
  String get reloadedFromHost => 'أُعيد تحميل النسخة الحالية من المضيف';

  @override
  String get recentSearches => 'عمليات البحث الأخيرة';

  @override
  String get includeHiddenSubtitle =>
      'عرض النتائج المخفية أيضاً بواسطة إعدادات رؤية الملفات';

  @override
  String get writesRejected => 'الكتابة مرفوضة';

  @override
  String get phoneCanModify => 'يمكن لهذا الهاتف تعديل الملفات';

  @override
  String get allFoldersAllowed => 'جميع المجلدات مسموح بها';

  @override
  String get securityWarning =>
      'هذا الهاتف يتحكم بالكامل في المضيف. أي شخص يمكنه الوصول إليه يستطيع تغيير هذه الإعدادات والوصول إلى المجلدات المسموح بها.';

  @override
  String get thisDevice => 'هذا الجهاز';

  @override
  String get revokedStatus => 'مُلغى';

  @override
  String get activeStatus => 'نشط';

  @override
  String limitedTo(String path) {
    return 'مقيّد بـ: $path';
  }

  @override
  String get managedOnPc => 'يُدار من الحاسوب';

  @override
  String get osLabel => 'نظام التشغيل';

  @override
  String driveCapacityLine(String used, String total, String free) {
    return 'مُستخدَم $used من $total · $free متاح';
  }

  @override
  String driveCapacityLineOs(String used, String total, String free) {
    return 'مُستخدَم $used من $total · $free متاح · يحتوي نظام التشغيل';
  }

  @override
  String addedFolder(String path) {
    return 'أُضيف $path';
  }

  @override
  String removedFolder(String path) {
    return 'أُزيل $path';
  }

  @override
  String disconnectFailed(String error) {
    return 'فشل قطع الاتصال: $error';
  }

  @override
  String disconnectDeviceMessage(String pcName) {
    return 'قطع اتصال هذا الجهاز من $pcName؟ ستحتاج رمز اقتران جديداً لإعادة الاتصال.';
  }

  @override
  String get noCustomExtensions => 'لا يوجد — أضف امتداداً أدناه.';

  @override
  String get passphraseMismatch => 'عبارات المرور غير متطابقة';

  @override
  String get passphraseMinLength => 'يجب أن تكون عبارة المرور 6 أحرف على الأقل';

  @override
  String get usingDeviceVisibility => 'يستخدم رؤية خاصة بالجهاز';

  @override
  String get usingAppDefault => 'يستخدم الإعداد الافتراضي';

  @override
  String get followsAppDefaultVisibility =>
      'يتبع إعدادات رؤية الملفات الافتراضية للتطبيق ما لم تتجاوزها هنا.';

  @override
  String get overriddenForDevice => 'مُتجاوَز لهذا الجهاز';

  @override
  String usingAppDefaultLabel(String label) {
    return 'يستخدم الإعداد الافتراضي ($label)';
  }

  @override
  String get checkingForUpdates => 'جارٍ التحقق من التحديثات…';

  @override
  String get updateNotCompleted => 'لم يكتمل التحديث — انقر لإعادة المحاولة.';

  @override
  String get openingInstallerConfirm =>
      'جارٍ فتح المثبّت — أكّد في Android ثم عُد إلى هنا.';

  @override
  String get downloadPaused =>
      'توقف التنزيل. أعد المحاولة للاستئناف من حيث توقف.';

  @override
  String get exportConfigSubtitle =>
      'حفظ الأجهزة المقترنة والرموز والمفضلة والإعدادات في ملف مشفّر';

  @override
  String get backupEncryptionWarning =>
      'النسخ الاحتياطية مشفّرة بعبارة المرور الخاصة بك. إذا فقدتها لا يمكن استعادة النسخة الاحتياطية.';

  @override
  String get preparingBackup => 'جارٍ إعداد النسخة الاحتياطية…';

  @override
  String get backupReadyToShare => 'النسخة الاحتياطية جاهزة للمشاركة';

  @override
  String get exportFailed => 'فشل التصدير';

  @override
  String couldNotReadFile(String error) {
    return 'تعذّرت قراءة الملف: $error';
  }

  @override
  String get importWarningMessage =>
      'الاستيراد يستبدل جميع الأجهزة والرموز والإعدادات الحالية على هذا الجهاز. هل تريد المتابعة؟';

  @override
  String get restoringConfig => 'جارٍ استعادة الإعدادات…';

  @override
  String get configRestored =>
      'تمت استعادة الإعدادات. للحصول على أفضل النتائج، أغلق التطبيق وأعد فتحه بالكامل.';

  @override
  String get importFailed => 'فشل الاستيراد';

  @override
  String get ascendingTooltip => 'تصاعدي';

  @override
  String get descendingTooltip => 'تنازلي';

  @override
  String get pausedStatus => 'متوقف مؤقتاً';

  @override
  String get verifiedLabel => 'تم التحقق';

  @override
  String get metaPath => 'المسار';

  @override
  String get metaSize => 'الحجم';

  @override
  String get metaType => 'النوع';

  @override
  String get metaPermissions => 'الأذونات';

  @override
  String get metaModified => 'تاريخ التعديل';

  @override
  String get metaCreated => 'تاريخ الإنشاء';

  @override
  String get metaSymlink => 'رابط رمزي';

  @override
  String get noLabel => 'لا';

  @override
  String couldNotDuplicate(String name) {
    return 'تعذّر نسخ \"$name\"';
  }

  @override
  String restoredItem(String name) {
    return 'تمت استعادة \"$name\"';
  }

  @override
  String restoreFailed(String error) {
    return 'فشلت الاستعادة: $error';
  }

  @override
  String deleteForeverConfirm(String name) {
    return 'حذف \"$name\" نهائياً؟ لا يمكن التراجع عن ذلك.';
  }

  @override
  String deletedForever(String name) {
    return 'حُذف \"$name\" نهائياً';
  }

  @override
  String emptyTrashBody(int count) {
    return 'حذف جميع العناصر ($count) نهائياً؟ لا يمكن التراجع عن ذلك.';
  }

  @override
  String get trashEmptied => 'تم إفراغ سلة المهملات';

  @override
  String emptyFailed(String error) {
    return 'فشل الإفراغ: $error';
  }

  @override
  String get trashIsEmpty => 'سلة المهملات فارغة';

  @override
  String get trashEmptySubtitle => 'العناصر المحذوفة تظهر هنا ويمكن استعادتها.';

  @override
  String deletedRelative(String relative) {
    return 'حُذف $relative';
  }

  @override
  String copyItemsTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
    );
    return 'نسخ $_temp0 إلى…';
  }

  @override
  String moveItemsTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      few: '$count عناصر',
      two: 'عنصرين',
      one: 'عنصر واحد',
    );
    return 'نقل $_temp0 إلى…';
  }

  @override
  String get copyHereButton => 'نسخ هنا';

  @override
  String get moveHereButton => 'نقل هنا';

  @override
  String get downloadingEllipsis => 'جارٍ التنزيل…';

  @override
  String get transfersTitle => 'عمليات النقل';

  @override
  String get transferGroupActive => 'نشطة';

  @override
  String get transferGroupQueued => 'في الانتظار';

  @override
  String get transferGroupDone => 'مكتملة';

  @override
  String get transferGroupFailed => 'فاشلة';

  @override
  String get followsDefaultsOverrideHint =>
      'تتبع إعدادات التطبيق الافتراضية ما لم تُغيّرها هنا.';

  @override
  String get importReplacesBody =>
      'الاستيراد يستبدل جميع الأجهزة المقترنة والرموز والإعدادات على هذا الجهاز. متابعة؟';

  @override
  String get searchCategoryFolders => 'مجلدات';

  @override
  String get searchCategoryImages => 'صور';

  @override
  String get searchCategoryVideos => 'فيديو';

  @override
  String get searchCategoryAudio => 'صوتيات';

  @override
  String get searchCategoryDocs => 'مستندات';

  @override
  String get searchCategoryArchives => 'أرشيف';

  @override
  String get searchCategoryOther => 'أخرى';

  @override
  String get sizePresetAny => 'أي حجم';

  @override
  String get sizePresetMb1 => '> 1 م.ب';

  @override
  String get sizePresetMb10 => '> 10 م.ب';

  @override
  String get sizePresetMb100 => '> 100 م.ب';

  @override
  String get sizePresetGb1 => '> 1 غ.ب';

  @override
  String get datePresetAny => 'أي وقت';

  @override
  String get datePresetLast24h => 'آخر 24 ساعة';

  @override
  String get datePresetLast7d => 'آخر 7 أيام';

  @override
  String get datePresetLast30d => 'آخر 30 يومًا';

  @override
  String get datePresetThisYear => 'هذا العام';

  @override
  String get wakeButton => 'إيقاظ';

  @override
  String wolPacketSent(String hostname) {
    return 'تم إرسال حزمة الإيقاظ إلى $hostname';
  }

  @override
  String get wolPacketFailed => 'فشل إرسال حزمة الإيقاظ';

  @override
  String previewPageIndicator(int current, int total) {
    return '$current من $total';
  }

  @override
  String get bandwidthSection => 'عرض النطاق';

  @override
  String get bandwidthUploadLimit => 'حد الرفع';

  @override
  String get bandwidthDownloadLimit => 'حد التنزيل';

  @override
  String get bandwidthUnlimited => 'بلا حدود';

  @override
  String get cacheSection => 'ذاكرة التخزين';

  @override
  String get cacheListingLabel => 'قوائم المجلدات';

  @override
  String get cacheTempLabel => 'الملفات المحمّلة';

  @override
  String get cacheTotalLabel => 'الإجمالي';

  @override
  String get cacheClearAll => 'مسح كل التخزين المؤقت';

  @override
  String get cacheCleared => 'تم مسح التخزين المؤقت';

  @override
  String get cacheCalculating => 'جارٍ الحساب…';

  @override
  String get onboardingWelcomeTitle => 'مرحباً في مستكشف الملفات عن بُعد';

  @override
  String get onboardingWelcomeBody =>
      'تصفّح وأدِر وانقل الملفات بين هاتفك وأي حاسوب على شبكتك.';

  @override
  String get onboardingHowTitle => 'كيف يعمل';

  @override
  String get onboardingHowBody =>
      'ثبّت الوكيل على حاسوبك، وقرنه مع هذا التطبيق برمز لمرة واحدة — عبر الواي فاي أو Tailscale.';

  @override
  String get onboardingReadyTitle => 'جاهز للبدء';

  @override
  String get onboardingReadyBody =>
      'قرن أول حاسوب لبدء الاستكشاف. ملفاتك تبقى على أجهزتك — لا شيء يذهب إلى السحابة.';

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingBack => 'رجوع';

  @override
  String get onboardingGetStarted => 'ابدأ';
}
