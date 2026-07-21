# Room/WorkManager generated implementation classes are constructed via
# reflection at runtime; R8 was stripping their no-arg constructors with no
# keep rule in place (crash: NoSuchMethodException: WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.*_Impl { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}
