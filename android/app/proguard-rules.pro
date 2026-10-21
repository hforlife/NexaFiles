# junrar logs through slf4j; without a binding slf4j falls back to a no-op
# logger at runtime, so the optional binder class may be absent.
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.slf4j.impl.StaticMDCBinder
-dontwarn org.slf4j.impl.StaticMarkerBinder
