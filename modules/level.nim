# Copyright 2016 Xored Software, Inc.

type
  FLevelSimplificationDetails* {.header: "Engine/Level.h", importcpp.} = object
    bCreatePackagePerAsset*: bool
      ## Whether to create separate packages for each generated asset. All in map package otherwise
      ## UPROPERTY(Category=General, EditAnywhere)
    detailsPercentage* {.importcpp: "DetailsPercentage".}: cfloat
      ## Percentage of details for static mesh proxy
      ## UPROPERTY(Category=StaticMesh, EditAnywhere, meta=(DisplayName="Static Mesh Details Percentage", ClampMin = "0", ClampMax = "100", UIMin = "0", UIMax = "100"))
    staticMeshMaterialSettings* {.importcpp: "StaticMeshMaterialSettings".}: FMaterialProxySettings
      ## Landscape material simplification
      ## UPROPERTY(Category = Landscape, EditAnywhere)
    bOverrideLandscapeExportLOD*: bool
      ## UPROPERTY()
    landscapeExportLOD* {.importcpp: "LandscapeExportLOD".}: int32
      ## Landscape LOD to use for static mesh generation, when not specified 'Max LODLevel' from landscape actor will be used
      ## UPROPERTY(Category=Landscape, EditAnywhere, meta=(ClampMin = "0", ClampMax = "7", UIMin = "0", UIMax = "7", editcondition = "bOverrideLandscapeExportLOD"))
    landscapeMaterialSettings* {.importcpp: "LandscapeMaterialSettings".}: FMaterialProxySettings
      ## Landscape material simplification
      ## UPROPERTY(Category = Landscape, EditAnywhere)
    bBakeFoliageToLandscape*: bool
      ## Whether to bake foliage into landscape static mesh texture
      ## UPROPERTY(Category=Landscape, EditAnywhere)
    bBakeGrassToLandscape*: bool
      ## Whether to bake grass into landscape static mesh texture
      ## UPROPERTY(Category=Landscape, EditAnywhere)

  FPrecomputedLightVolume* {.header: "PrecomputedLightVolume.h", importcpp.} = object

  FStreamableTextureInstance* {.header: "Engine/Level.h", importcpp, inheritable, bycopy.} = object
    ## Structure containing all information needed for determining the screen space
    ## size of an object/ texture instance.
    boundingSphere {.importcpp: "BoundingSphere".}: FSphere
      ## Bounding sphere/ box of object
    minDistance {.importcpp: "MinDistance".}: cfloat
      ## Min distance from view where this instance is usable
    maxDistance {.importcpp: "MaxDistance".}: cfloat
      ## Max distance from view where this instance is usable
    texelFactor {.importcpp: "TexelFactor".}: cfloat
      ## Object (and bounding sphere) specific texel scale factor

  FDynamicTextureInstance* {.header: "Engine/Level.h", importcpp, bycopy.} = object of FStreamableTextureInstance
    ## Serialized ULevel information about dynamic texture instances
    texture* {.importcpp: "Texture".}: ptr UTexture2D
      ## Texture that is used by a dynamic UPrimitiveComponent.
    bAttached*: bool
      ## Whether the primitive that uses this texture is attached to the scene or not.
    originalRadius* {.importcpp: "OriginalRadius".}: cfloat
      ## Original bounding sphere radius, at the time the TexelFactor was calculated originally.

declareBuiltinDelegate(FLevelBoundsActorUpdatedEvent, dkMulticast, "Engine/Level.h")
declareBuiltinDelegate(FLevelTransformEvent, dkMulticast, "Engine/Level.h", transform: FTransform)

class(FPrecomputedVisibilityHandler, header: "Engine/Level.h"):
  ## Handles operations on precomputed visibility data for a level.
  proc updateVisibilityStats(bAllocating: bool) {.noSideEffect.}
    ## Updates visibility stats.
  proc updateScene(scene: ptr FSceneInterface) {.noSideEffect.}
    ## Sets this visibility handler to be actively used by the rendering scene.
  proc invalidate(scene: ptr FSceneInterface)
    ## Invalidates the level's precomputed visibility and frees any memory used by the handler.
  proc applyWorldOffset(inOffset: FVector)
    ## Shifts origin of precomputed visibility volume by specified offset
  proc getId(): int32 {.noSideEffect.}
    ## @return the Id

class(FPrecomputedVolumeDistanceField, header: "Engine/Level.h"):
  ## Volume distance field generated by Lightmass, used by image based reflections for shadowing. */
  proc updateScene(scene: ptr FSceneInterface) {.noSideEffect.}
    ## Sets this volume distance field to be actively used by the rendering scene.
  proc invalidate(scene: ptr FSceneInterface)
    ## Invalidates the level's volume distance field and frees any memory used by it.

class(ULevel of UObject, header: "Engine/Level.h", notypedef):
  var URL: FURL
    ## URL associated with this level.

  var streamedLevelsOwningWorld: TMap[FName, TWeakObjectPtr[UWorld]]
    ## Set before calling LoadPackage for a streaming level to ensure that OwningWorld is correct on the Level

  var owningWorld: ptr UWorld
    ## The World that has this level in its Levels array.
    ## This is not the same as GetOuter(), because GetOuter() for a streaming level is a vestigial world that is not used.
    ## It should not be accessed during BeginDestroy(), just like any other UObject references, since GC may occur in any order.
    ##
    ## UPROPERTY(transient)

  var model: ptr UModel
    ## BSP UModel.
    ## UPROPERTY()

  var modelComponents: TArray[ptr UModelComponent]
    ## BSP Model components used for rendering.
    ## UPROPERTY()

# when WITH_EDITORONLY_DATA:
  var levelScriptBlueprint: ptr ULevelScriptBlueprint
    ## Reference to the blueprint for level scripting
    ## UPROPERTY(NonTransactional)
#endwhen

  var levelScriptActor: ptr ALevelScriptActor
    ## The level scripting actor, created by instantiating the class from LevelScriptBlueprint.  This handles all level scripting
    ## UPROPERTY(NonTransactional)

  var navListEnd: ptr ANavigationObjectBase
    ## UPROPERTY()

  var navDataChunks: TArray[ptr UNavigationDataChunk]
    ## Navigation related data that can be stored per level
    ## UPROPERTY()

  var lightmapTotalSize: cfloat
    ## Total number of KB used for lightmap textures in the level.
    ## UPROPERTY(VisibleAnywhere, Category=Level)

  var shadowmapTotalSize: cfloat
    ## Total number of KB used for shadowmap textures in the level.
    ## UPROPERTY(VisibleAnywhere, Category=Level)

  var staticNavigableGeometry: TArray[FVector]
    ## threes of triangle vertices - AABB filtering friendly. Stored if there's a runtime need to rebuild navigation that accepts BSPs
    ## 	as well - it's a lot easier this way than retrieve this data at runtime
    ## UPROPERTY()

  var textureToInstancesMap: TMap[ptr UTexture2D, TArray[FStreamableTextureInstance]]
    ## Static information used by texture streaming code, generated during PreSave

  var dynamicTextureInstances: TMap[TWeakObjectPtr[UPrimitiveComponent],
                                  TArray[FDynamicTextureInstance]]
    ## Information about textures on dynamic primitives. Used by texture streaming code, generated during PreSave.

  var forceStreamTextures: TMap[ptr UTexture2D, bool]
    ## Set of textures used by PrimitiveComponents that have bForceMipStreaming checked.

  var iFirstNetRelevantActor: int32
    ## Index into Actors array pointing to first net relevant actor. Used as an optimization for FActorIterator

  var precomputedLightVolume: ptr FPrecomputedLightVolume
    ## The precomputed light information for this level.
    ## The extra level of indirection is to allow forward declaring FPrecomputedLightVolume.

  var precomputedVisibilityHandler: FPrecomputedVisibilityHandler
    ## Contains precomputed visibility data for this level.

  var precomputedVolumeDistanceField: FPrecomputedVolumeDistanceField
    ## Precomputed volume distance field for this level.

  var removeFromSceneFence: FRenderCommandFence
    ## Fence used to track when the rendering thread has finished referencing this ULevel's resources.

  var bAreComponentsCurrentlyRegistered1: bool
    ## Whether components are currently registered or not.

  var bGeometryDirtyForLighting1: bool
    ## Whether the geometry needs to be rebuilt for correct lighting

  var bTextureStreamingBuilt1: bool
    ## Has texture streaming been built

  var bIsVisible1: bool
    ## Whether the level is currently visible/ associated with the world
    ## UPROPERTY(transient)

  var bLocked1: bool
    ## Whether this level is locked; that is, its actors are read-only
    ## 	Used by WorldBrowser to lock a level when corresponding ULevelStreaming does not exist
    ##
    ## UPROPERTY()

  var bAlreadyMovedActors1: bool
    ## The below variables are used temporarily while making a level visible.
    ## Whether we already moved actors.

  var bAlreadyShiftedActors1: bool
    ## Whether we already shift actors positions according to world composition.

  var bAlreadyUpdatedComponents1: bool
    ## Whether we already updated components.

  var bAlreadyAssociatedStreamableResources1: bool
    ## Whether we already associated streamable resources.

  var bAlreadyInitializedNetworkActors1: bool
    ## Whether we already initialized network actors.

  var bAlreadyRoutedActorInitialize1: bool
    ## Whether we already routed initialize on actors.

  var bAlreadySortedActorList1: bool
    ## Whether we already sorted the actor list.

  var bIsAssociatingLevel1: bool
    ## Whether this level is in the process of being associated with its world

  var bRequireFullVisibilityToRender1: bool
    ## Whether this level should be fully added to the world before rendering his components

  var bClientOnlyVisible1: bool
    ## Whether this level is specific to client, visibility state will not be replicated to server

  var bWasDuplicatedForPIE1: bool
    ## Whether this level was duplicated for PIE

  var currentActorIndexForUpdateComponents: int32
    ## Current index into actors array for updating components.

  proc hasVisibilityRequestPending(): bool {.noSideEffect.}
    ## Whether the level is currently pending being made visible.

  var onApplyLevelTransform: FLevelTransformEvent
    ## Event on level transform changes

# when WITH_EDITORONLY_DATA:
  var levelSimplification: array[4, FLevelSimplificationDetails]
    ## Level simplification settings for each LOD
    ## UPROPERTY()

  var levelColor: FLinearColor
    ## The level color used for visualization. (Show -> Advanced -> Level Coloration)
    ## Used only in world composition mode
    ##
    ## UPROPERTY()
# endwhen

  var levelBoundsActor: TWeakObjectPtr[ALevelBounds]
    ## Actor which defines level logical bounding box

  var instancedFoliageActor: TWeakObjectPtr[AInstancedFoliageActor]
    ## Cached pointer to Foliage actor

  proc levelBoundsActorUpdated(): var FLevelBoundsActorUpdatedEvent
    ## Called when Level bounds actor has been updated

  proc broadcastLevelBoundsActorUpdated()
    ##*	Broadcasts that Level bounds actor has been updated

  proc markLevelBoundsDirty()
    ## Marks level bounds as dirty so they will be recalculated

  var assetUserData: TArray[ptr UAssetUserData]
    ## Array of user data stored with the asset
    ## UPROPERTY()


  # var levelDirtiedEvent: FSimpleMulticastDelegate
  # ## Called when a level package has been dirtied.

  proc initialize(inURL: FURL)

  proc clearLevelComponents()
    ## Clears all components of actors associated with this level (aka in Actors array) and
    ## also the BSP model components.

  proc updateLevelComponents(bRerunConstructionScripts: bool)
    ## Updates all components of actors associated with this level (aka in Actors array) and
    ## creates the BSP model components.
    ## @param bRerunConstructionScripts	If we want to rerun construction scripts on actors in level

  proc incrementalUpdateComponents(numComponentsToUpdate: int32;
                                  bRerunConstructionScripts: bool)
    ## Incrementally updates all components of actors associated with this level.
    ##
    ## @param NumComponentsToUpdate		Number of components to update in this run, 0 for all
    ## @param bRerunConstructionScripts	If we want to rerun construction scripts on actors in level

  proc invalidateModelGeometry()
    ## Invalidates the cached data used to render the level's UModel.

# when WITH_EDITOR:
  proc markLevelComponentsRenderStateDirty()
    ## Marks all level components render state as dirty
  proc createModelComponents()
    ## Called to create ModelComponents for BSP rendering
# endwhen

  proc updateModelComponents()
    ## Updates the model components associated with this level

  proc commitModelSurfaces()
    ## Commits changes made to the UModel's surfaces.

  proc invalidateModelSurface()
    ## Discards the cached data used to render the level's UModel.  Assumes that the
    ## faces and vertex positions haven't changed, only the applied materials.

  proc validateLightGUIDs()
    ## Makes sure that all light components have valid GUIDs associated.

  proc sortActorList()
    ## Sorts the actor list by net relevancy and static behaviour. First all not net relevant static
    ## actors, then all net relevant static actors and then the rest. This is done to allow the dynamic
    ## and net relevant actor iterators to skip large amounts of actors.

  proc isNameStableForNetworking(): bool {.noSideEffect.}

  proc initializeNetworkActors()
    ## For now, assume all levels have stable net names
    ## Handles network initialization for actors in this level

  proc initializeRenderingResources()
    ## Initializes rendering resources for this level.

  proc releaseRenderingResources()
    ## Releases rendering resources for this level.

  proc routeActorInitialize()
    ## Routes pre and post initialize to actors and also sets volumes.
    ##
    ## @todo seamless worlds: this doesn't correctly handle volumes in the multi- level case

  proc buildStreamingData(world: ptr UWorld; targetLevel: ptr ULevel = nil;
                          targetTexture: ptr UTexture2D = nil)
    ## Rebuilds static streaming data for all levels in the specified UWorld.
    ##
    ## @param World				Which world to rebuild streaming data for. If NULL, all worlds will be processed.
    ## @param TargetLevel		[opt] Specifies a single level to process. If NULL, all levels will be processed.
    ## @param TargetTexture		[opt] Specifies a single texture to process. If NULL, all textures will be processed.

  proc buildStreamingData(targetTexture: ptr UTexture2D = nil)
    ## Rebuilds static streaming data for this level.
    ##
    ## @param TargetTexture			[opt] Specifies a single texture to process. If NULL, all textures will be processed.

  proc normalizeLightmapTexelFactor()
    ## Clamp lightmap and shadowmap texelfactors to 20-80% range.
    ## This is to prevent very low-res or high-res charts to dominate otherwise decent streaming.

  proc getStreamableTextureInstances(targetTexture: var ptr UTexture2D): ptr TArray[
      FStreamableTextureInstance]
    ## Retrieves the array of streamable texture isntances.

  proc getDefaultBrush(): ptr ABrush {.noSideEffect.}
    ## Returns the default brush for this level.
    ##
    ## @return		The default brush for this level.

  proc getWorldSettings(): ptr AWorldSettings {.noSideEffect.}
    ## Returns the world info for this level.
    ##
    ## @return		The AWorldSettings for this level.

  proc getLevelScriptActor(): ptr ALevelScriptActor {.noSideEffect.}
    ## Returns the level scripting actor associated with this level
    ## @return	a pointer to the level scripting actor for this level (may be NULL)

  proc hasAnyActorsOfType(searchType: ptr UClass): bool
    ## Utility searches this level's actor list for any actors of the specified type.

  proc resetNavList()
    ## Resets the level nav list.

# when WITH_EDITOR:
  proc getLevelScriptBlueprint(bDontCreate: bool = false): ptr ULevelScriptBlueprint
    ## 	Grabs a reference to the level scripting blueprint for this level.  If none exists, it creates a new blueprint
    ##
    ## @param	bDontCreate		If true, if no level scripting blueprint is found, none will be created
  proc getLevelBlueprints(): TArray[ptr UBlueprint] {.noSideEffect.}
    ## Returns a list of all blueprints contained within the level
  proc onLevelScriptBlueprintChanged(inBlueprint: ptr ULevelScriptBlueprint)
    ## Called when the level script blueprint has been successfully changed and compiled.  Handles creating an instance of the blueprint class in LevelScriptActor
# endwhen

  proc getStaticNavigableGeometry(): ptr TArray[FVector] {.noSideEffect.}
    ## @todo document

  proc isPersistentLevel(): bool {.noSideEffect.}
    ## Is this the persistent level

  proc isCurrentLevel(): bool {.noSideEffect.}
    ## Is this the current level in the world it is owned by

  proc applyWorldOffset(inWorldOffset: FVector; bWorldShift: bool)
    ## Shift level actors by specified offset
    ## The offset vector will get subtracted from all actors positions and corresponding data structures
    ##
    ## @param InWorldOffset	 Vector to shift all actors by
    ## @param bWorldShift	 Whether this call is part of whole world shifting

  proc registerActorForAutoReceiveInput(actor: ptr AActor; playerIndex: int32)
    ## Register an actor that should be added to a player's input stack when they are created


  proc pushPendingAutoReceiveInput(PC: ptr APlayerController)
    ## Push any pending auto receive input actor's input components on to the player controller's input stack
# when WITH_EDITOR:
  proc rebuildStaticNavigableGeometry()
    ## meant to be called only from editor, calculating and storing static geometry to be used with off-line and/or on-line navigation building
# endwhen