# Copyright 2017 Xored Software, Inc.

proc setGlobalTimeDilation*(worldContextObject: ptr UObject, timeDilation: cfloat) {.
  header: "Kismet/GameplayStatics.h", importcpp:"UGameplayStatics::SetGlobalTimeDilation(@)".}
  
proc getGlobalTimeDilation*(worldContextObject: ptr UObject): cfloat {.
  header: "Kismet/GameplayStatics.h", importcpp:"UGameplayStatics::GetGlobalTimeDilation(@)".}