--
-- Encodings of extension objects.
-- created by "/home/treww/src/barracuda/xrc/lua/opcua/schemas/generate_protocol_lua.py"
--
local a = require("opcua.binary.encode_types_gen")
local tenc = a.Encoder
local tdec = a.Decoder
tdec["i=260"] = tdec.node
tenc["i=260"] = tenc.node
tdec["i=263"] = tdec.objectNode
tenc["i=263"] = tenc.objectNode
tdec["i=266"] = tdec.objectTypeNode
tenc["i=266"] = tenc.objectTypeNode
tdec["i=269"] = tdec.variableNode
tenc["i=269"] = tenc.variableNode
tdec["i=272"] = tdec.variableTypeNode
tenc["i=272"] = tenc.variableTypeNode
tdec["i=275"] = tdec.referenceTypeNode
tenc["i=275"] = tenc.referenceTypeNode
tdec["i=278"] = tdec.methodNode
tenc["i=278"] = tenc.methodNode
tdec["i=281"] = tdec.viewNode
tenc["i=281"] = tenc.viewNode
tdec["i=284"] = tdec.dataTypeNode
tenc["i=284"] = tenc.dataTypeNode
tdec["i=287"] = tdec.referenceNode
tenc["i=287"] = tenc.referenceNode
tdec["i=298"] = tdec.argument
tenc["i=298"] = tenc.argument
tdec["i=301"] = tdec.statusResult
tenc["i=301"] = tenc.statusResult
tdec["i=306"] = tdec.userTokenPolicy
tenc["i=306"] = tenc.userTokenPolicy
tdec["i=310"] = tdec.applicationDescription
tenc["i=310"] = tenc.applicationDescription
tdec["i=314"] = tdec.endpointDescription
tenc["i=314"] = tenc.endpointDescription
tdec["i=318"] = tdec.userIdentityToken
tenc["i=318"] = tenc.userIdentityToken
tdec["i=321"] = tdec.anonymousIdentityToken
tenc["i=321"] = tenc.anonymousIdentityToken
tdec["i=324"] = tdec.userNameIdentityToken
tenc["i=324"] = tenc.userNameIdentityToken
tdec["i=327"] = tdec.x509identityToken
tenc["i=327"] = tenc.x509identityToken
tdec["i=333"] = tdec.endpointConfiguration
tenc["i=333"] = tenc.endpointConfiguration
tdec["i=337"] = tdec.supportedProfile
tenc["i=337"] = tenc.supportedProfile
tdec["i=340"] = tdec.buildInfo
tenc["i=340"] = tenc.buildInfo
tdec["i=343"] = tdec.softwareCertificate
tenc["i=343"] = tenc.softwareCertificate
tdec["i=346"] = tdec.signedSoftwareCertificate
tenc["i=346"] = tenc.signedSoftwareCertificate
tdec["i=351"] = tdec.nodeAttributes
tenc["i=351"] = tenc.nodeAttributes
tdec["i=354"] = tdec.objectAttributes
tenc["i=354"] = tenc.objectAttributes
tdec["i=357"] = tdec.variableAttributes
tenc["i=357"] = tenc.variableAttributes
tdec["i=360"] = tdec.methodAttributes
tenc["i=360"] = tenc.methodAttributes
tdec["i=363"] = tdec.objectTypeAttributes
tenc["i=363"] = tenc.objectTypeAttributes
tdec["i=366"] = tdec.variableTypeAttributes
tenc["i=366"] = tenc.variableTypeAttributes
tdec["i=369"] = tdec.referenceTypeAttributes
tenc["i=369"] = tenc.referenceTypeAttributes
tdec["i=372"] = tdec.dataTypeAttributes
tenc["i=372"] = tenc.dataTypeAttributes
tdec["i=375"] = tdec.viewAttributes
tenc["i=375"] = tenc.viewAttributes
tdec["i=378"] = tdec.addNodesItem
tenc["i=378"] = tenc.addNodesItem
tdec["i=381"] = tdec.addReferencesItem
tenc["i=381"] = tenc.addReferencesItem
tdec["i=384"] = tdec.deleteNodesItem
tenc["i=384"] = tenc.deleteNodesItem
tdec["i=387"] = tdec.deleteReferencesItem
tenc["i=387"] = tenc.deleteReferencesItem
tdec["i=391"] = tdec.requestHeader
tenc["i=391"] = tenc.requestHeader
tdec["i=394"] = tdec.responseHeader
tenc["i=394"] = tenc.responseHeader
tdec["i=397"] = tdec.serviceFault
tenc["i=397"] = tenc.serviceFault
tdec["i=401"] = tdec.scalarTestType
tenc["i=401"] = tenc.scalarTestType
tdec["i=404"] = tdec.arrayTestType
tenc["i=404"] = tenc.arrayTestType
tdec["i=407"] = tdec.compositeTestType
tenc["i=407"] = tenc.compositeTestType
tdec["i=410"] = tdec.testStackRequest
tenc["i=410"] = tenc.testStackRequest
tdec["i=413"] = tdec.testStackResponse
tenc["i=413"] = tenc.testStackResponse
tdec["i=416"] = tdec.testStackExRequest
tenc["i=416"] = tenc.testStackExRequest
tdec["i=419"] = tdec.testStackExResponse
tenc["i=419"] = tenc.testStackExResponse
tdec["i=422"] = tdec.findServersRequest
tenc["i=422"] = tenc.findServersRequest
tdec["i=425"] = tdec.findServersResponse
tenc["i=425"] = tenc.findServersResponse
tdec["i=428"] = tdec.getEndpointsRequest
tenc["i=428"] = tenc.getEndpointsRequest
tdec["i=431"] = tdec.getEndpointsResponse
tenc["i=431"] = tenc.getEndpointsResponse
tdec["i=434"] = tdec.registeredServer
tenc["i=434"] = tenc.registeredServer
tdec["i=437"] = tdec.registerServerRequest
tenc["i=437"] = tenc.registerServerRequest
tdec["i=440"] = tdec.registerServerResponse
tenc["i=440"] = tenc.registerServerResponse
tdec["i=443"] = tdec.channelSecurityToken
tenc["i=443"] = tenc.channelSecurityToken
tdec["i=446"] = tdec.openSecureChannelRequest
tenc["i=446"] = tenc.openSecureChannelRequest
tdec["i=449"] = tdec.openSecureChannelResponse
tenc["i=449"] = tenc.openSecureChannelResponse
tdec["i=452"] = tdec.closeSecureChannelRequest
tenc["i=452"] = tenc.closeSecureChannelRequest
tdec["i=455"] = tdec.closeSecureChannelResponse
tenc["i=455"] = tenc.closeSecureChannelResponse
tdec["i=458"] = tdec.signatureData
tenc["i=458"] = tenc.signatureData
tdec["i=461"] = tdec.createSessionRequest
tenc["i=461"] = tenc.createSessionRequest
tdec["i=464"] = tdec.createSessionResponse
tenc["i=464"] = tenc.createSessionResponse
tdec["i=467"] = tdec.activateSessionRequest
tenc["i=467"] = tenc.activateSessionRequest
tdec["i=470"] = tdec.activateSessionResponse
tenc["i=470"] = tenc.activateSessionResponse
tdec["i=473"] = tdec.closeSessionRequest
tenc["i=473"] = tenc.closeSessionRequest
tdec["i=476"] = tdec.closeSessionResponse
tenc["i=476"] = tenc.closeSessionResponse
tdec["i=479"] = tdec.cancelRequest
tenc["i=479"] = tenc.cancelRequest
tdec["i=482"] = tdec.cancelResponse
tenc["i=482"] = tenc.cancelResponse
tdec["i=485"] = tdec.addNodesResult
tenc["i=485"] = tenc.addNodesResult
tdec["i=488"] = tdec.addNodesRequest
tenc["i=488"] = tenc.addNodesRequest
tdec["i=491"] = tdec.addNodesResponse
tenc["i=491"] = tenc.addNodesResponse
tdec["i=494"] = tdec.addReferencesRequest
tenc["i=494"] = tenc.addReferencesRequest
tdec["i=497"] = tdec.addReferencesResponse
tenc["i=497"] = tenc.addReferencesResponse
tdec["i=500"] = tdec.deleteNodesRequest
tenc["i=500"] = tenc.deleteNodesRequest
tdec["i=503"] = tdec.deleteNodesResponse
tenc["i=503"] = tenc.deleteNodesResponse
tdec["i=506"] = tdec.deleteReferencesRequest
tenc["i=506"] = tenc.deleteReferencesRequest
tdec["i=509"] = tdec.deleteReferencesResponse
tenc["i=509"] = tenc.deleteReferencesResponse
tdec["i=513"] = tdec.viewDescription
tenc["i=513"] = tenc.viewDescription
tdec["i=516"] = tdec.browseDescription
tenc["i=516"] = tenc.browseDescription
tdec["i=520"] = tdec.referenceDescription
tenc["i=520"] = tenc.referenceDescription
tdec["i=524"] = tdec.browseResult
tenc["i=524"] = tenc.browseResult
tdec["i=527"] = tdec.browseRequest
tenc["i=527"] = tenc.browseRequest
tdec["i=530"] = tdec.browseResponse
tenc["i=530"] = tenc.browseResponse
tdec["i=533"] = tdec.browseNextRequest
tenc["i=533"] = tenc.browseNextRequest
tdec["i=536"] = tdec.browseNextResponse
tenc["i=536"] = tenc.browseNextResponse
tdec["i=539"] = tdec.relativePathElement
tenc["i=539"] = tenc.relativePathElement
tdec["i=542"] = tdec.relativePath
tenc["i=542"] = tenc.relativePath
tdec["i=545"] = tdec.browsePath
tenc["i=545"] = tenc.browsePath
tdec["i=548"] = tdec.browsePathTarget
tenc["i=548"] = tenc.browsePathTarget
tdec["i=551"] = tdec.browsePathResult
tenc["i=551"] = tenc.browsePathResult
tdec["i=554"] = tdec.translateBrowsePathsToNodeIdsRequest
tenc["i=554"] = tenc.translateBrowsePathsToNodeIdsRequest
tdec["i=557"] = tdec.translateBrowsePathsToNodeIdsResponse
tenc["i=557"] = tenc.translateBrowsePathsToNodeIdsResponse
tdec["i=560"] = tdec.registerNodesRequest
tenc["i=560"] = tenc.registerNodesRequest
tdec["i=563"] = tdec.registerNodesResponse
tenc["i=563"] = tenc.registerNodesResponse
tdec["i=566"] = tdec.unregisterNodesRequest
tenc["i=566"] = tenc.unregisterNodesRequest
tdec["i=569"] = tdec.unregisterNodesResponse
tenc["i=569"] = tenc.unregisterNodesResponse
tdec["i=572"] = tdec.queryDataDescription
tenc["i=572"] = tenc.queryDataDescription
tdec["i=575"] = tdec.nodeTypeDescription
tenc["i=575"] = tenc.nodeTypeDescription
tdec["i=579"] = tdec.queryDataSet
tenc["i=579"] = tenc.queryDataSet
tdec["i=582"] = tdec.nodeReference
tenc["i=582"] = tenc.nodeReference
tdec["i=585"] = tdec.contentFilterElement
tenc["i=585"] = tenc.contentFilterElement
tdec["i=588"] = tdec.contentFilter
tenc["i=588"] = tenc.contentFilter
tdec["i=591"] = tdec.filterOperand
tenc["i=591"] = tenc.filterOperand
tdec["i=594"] = tdec.elementOperand
tenc["i=594"] = tenc.elementOperand
tdec["i=597"] = tdec.literalOperand
tenc["i=597"] = tenc.literalOperand
tdec["i=600"] = tdec.attributeOperand
tenc["i=600"] = tenc.attributeOperand
tdec["i=603"] = tdec.simpleAttributeOperand
tenc["i=603"] = tenc.simpleAttributeOperand
tdec["i=606"] = tdec.contentFilterElementResult
tenc["i=606"] = tenc.contentFilterElementResult
tdec["i=609"] = tdec.contentFilterResult
tenc["i=609"] = tenc.contentFilterResult
tdec["i=612"] = tdec.parsingResult
tenc["i=612"] = tenc.parsingResult
tdec["i=615"] = tdec.queryFirstRequest
tenc["i=615"] = tenc.queryFirstRequest
tdec["i=618"] = tdec.queryFirstResponse
tenc["i=618"] = tenc.queryFirstResponse
tdec["i=621"] = tdec.queryNextRequest
tenc["i=621"] = tenc.queryNextRequest
tdec["i=624"] = tdec.queryNextResponse
tenc["i=624"] = tenc.queryNextResponse
tdec["i=628"] = tdec.readValueId
tenc["i=628"] = tenc.readValueId
tdec["i=631"] = tdec.readRequest
tenc["i=631"] = tenc.readRequest
tdec["i=634"] = tdec.readResponse
tenc["i=634"] = tenc.readResponse
tdec["i=637"] = tdec.historyReadValueId
tenc["i=637"] = tenc.historyReadValueId
tdec["i=640"] = tdec.historyReadResult
tenc["i=640"] = tenc.historyReadResult
tdec["i=643"] = tdec.historyReadDetails
tenc["i=643"] = tenc.historyReadDetails
tdec["i=646"] = tdec.readEventDetails
tenc["i=646"] = tenc.readEventDetails
tdec["i=649"] = tdec.readRawModifiedDetails
tenc["i=649"] = tenc.readRawModifiedDetails
tdec["i=652"] = tdec.readProcessedDetails
tenc["i=652"] = tenc.readProcessedDetails
tdec["i=655"] = tdec.readAtTimeDetails
tenc["i=655"] = tenc.readAtTimeDetails
tdec["i=658"] = tdec.historyData
tenc["i=658"] = tenc.historyData
tdec["i=661"] = tdec.historyEvent
tenc["i=661"] = tenc.historyEvent
tdec["i=664"] = tdec.historyReadRequest
tenc["i=664"] = tenc.historyReadRequest
tdec["i=667"] = tdec.historyReadResponse
tenc["i=667"] = tenc.historyReadResponse
tdec["i=670"] = tdec.writeValue
tenc["i=670"] = tenc.writeValue
tdec["i=673"] = tdec.writeRequest
tenc["i=673"] = tenc.writeRequest
tdec["i=676"] = tdec.writeResponse
tenc["i=676"] = tenc.writeResponse
tdec["i=679"] = tdec.historyUpdateDetails
tenc["i=679"] = tenc.historyUpdateDetails
tdec["i=682"] = tdec.updateDataDetails
tenc["i=682"] = tenc.updateDataDetails
tdec["i=685"] = tdec.updateEventDetails
tenc["i=685"] = tenc.updateEventDetails
tdec["i=688"] = tdec.deleteRawModifiedDetails
tenc["i=688"] = tenc.deleteRawModifiedDetails
tdec["i=691"] = tdec.deleteAtTimeDetails
tenc["i=691"] = tenc.deleteAtTimeDetails
tdec["i=694"] = tdec.deleteEventDetails
tenc["i=694"] = tenc.deleteEventDetails
tdec["i=697"] = tdec.historyUpdateResult
tenc["i=697"] = tenc.historyUpdateResult
tdec["i=700"] = tdec.historyUpdateRequest
tenc["i=700"] = tenc.historyUpdateRequest
tdec["i=703"] = tdec.historyUpdateResponse
tenc["i=703"] = tenc.historyUpdateResponse
tdec["i=706"] = tdec.callMethodRequest
tenc["i=706"] = tenc.callMethodRequest
tdec["i=709"] = tdec.callMethodResult
tenc["i=709"] = tenc.callMethodResult
tdec["i=712"] = tdec.callRequest
tenc["i=712"] = tenc.callRequest
tdec["i=715"] = tdec.callResponse
tenc["i=715"] = tenc.callResponse
tdec["i=721"] = tdec.monitoringFilter
tenc["i=721"] = tenc.monitoringFilter
tdec["i=724"] = tdec.dataChangeFilter
tenc["i=724"] = tenc.dataChangeFilter
tdec["i=727"] = tdec.eventFilter
tenc["i=727"] = tenc.eventFilter
tdec["i=730"] = tdec.aggregateFilter
tenc["i=730"] = tenc.aggregateFilter
tdec["i=733"] = tdec.monitoringFilterResult
tenc["i=733"] = tenc.monitoringFilterResult
tdec["i=736"] = tdec.eventFilterResult
tenc["i=736"] = tenc.eventFilterResult
tdec["i=739"] = tdec.aggregateFilterResult
tenc["i=739"] = tenc.aggregateFilterResult
tdec["i=742"] = tdec.monitoringParameters
tenc["i=742"] = tenc.monitoringParameters
tdec["i=745"] = tdec.monitoredItemCreateRequest
tenc["i=745"] = tenc.monitoredItemCreateRequest
tdec["i=748"] = tdec.monitoredItemCreateResult
tenc["i=748"] = tenc.monitoredItemCreateResult
tdec["i=751"] = tdec.createMonitoredItemsRequest
tenc["i=751"] = tenc.createMonitoredItemsRequest
tdec["i=754"] = tdec.createMonitoredItemsResponse
tenc["i=754"] = tenc.createMonitoredItemsResponse
tdec["i=757"] = tdec.monitoredItemModifyRequest
tenc["i=757"] = tenc.monitoredItemModifyRequest
tdec["i=760"] = tdec.monitoredItemModifyResult
tenc["i=760"] = tenc.monitoredItemModifyResult
tdec["i=763"] = tdec.modifyMonitoredItemsRequest
tenc["i=763"] = tenc.modifyMonitoredItemsRequest
tdec["i=766"] = tdec.modifyMonitoredItemsResponse
tenc["i=766"] = tenc.modifyMonitoredItemsResponse
tdec["i=769"] = tdec.setMonitoringModeRequest
tenc["i=769"] = tenc.setMonitoringModeRequest
tdec["i=772"] = tdec.setMonitoringModeResponse
tenc["i=772"] = tenc.setMonitoringModeResponse
tdec["i=775"] = tdec.setTriggeringRequest
tenc["i=775"] = tenc.setTriggeringRequest
tdec["i=778"] = tdec.setTriggeringResponse
tenc["i=778"] = tenc.setTriggeringResponse
tdec["i=781"] = tdec.deleteMonitoredItemsRequest
tenc["i=781"] = tenc.deleteMonitoredItemsRequest
tdec["i=784"] = tdec.deleteMonitoredItemsResponse
tenc["i=784"] = tenc.deleteMonitoredItemsResponse
tdec["i=787"] = tdec.createSubscriptionRequest
tenc["i=787"] = tenc.createSubscriptionRequest
tdec["i=790"] = tdec.createSubscriptionResponse
tenc["i=790"] = tenc.createSubscriptionResponse
tdec["i=793"] = tdec.modifySubscriptionRequest
tenc["i=793"] = tenc.modifySubscriptionRequest
tdec["i=796"] = tdec.modifySubscriptionResponse
tenc["i=796"] = tenc.modifySubscriptionResponse
tdec["i=799"] = tdec.setPublishingModeRequest
tenc["i=799"] = tenc.setPublishingModeRequest
tdec["i=802"] = tdec.setPublishingModeResponse
tenc["i=802"] = tenc.setPublishingModeResponse
tdec["i=805"] = tdec.notificationMessage
tenc["i=805"] = tenc.notificationMessage
tdec["i=808"] = tdec.monitoredItemNotification
tenc["i=808"] = tenc.monitoredItemNotification
tdec["i=811"] = tdec.dataChangeNotification
tenc["i=811"] = tenc.dataChangeNotification
tdec["i=820"] = tdec.statusChangeNotification
tenc["i=820"] = tenc.statusChangeNotification
tdec["i=823"] = tdec.subscriptionAcknowledgement
tenc["i=823"] = tenc.subscriptionAcknowledgement
tdec["i=826"] = tdec.publishRequest
tenc["i=826"] = tenc.publishRequest
tdec["i=829"] = tdec.publishResponse
tenc["i=829"] = tenc.publishResponse
tdec["i=832"] = tdec.republishRequest
tenc["i=832"] = tenc.republishRequest
tdec["i=835"] = tdec.republishResponse
tenc["i=835"] = tenc.republishResponse
tdec["i=838"] = tdec.transferResult
tenc["i=838"] = tenc.transferResult
tdec["i=841"] = tdec.transferSubscriptionsRequest
tenc["i=841"] = tenc.transferSubscriptionsRequest
tdec["i=844"] = tdec.transferSubscriptionsResponse
tenc["i=844"] = tenc.transferSubscriptionsResponse
tdec["i=847"] = tdec.deleteSubscriptionsRequest
tenc["i=847"] = tenc.deleteSubscriptionsRequest
tdec["i=850"] = tdec.deleteSubscriptionsResponse
tenc["i=850"] = tenc.deleteSubscriptionsResponse
tdec["i=855"] = tdec.redundantServerDataType
tenc["i=855"] = tenc.redundantServerDataType
tdec["i=858"] = tdec.samplingIntervalDiagnosticsDataType
tenc["i=858"] = tenc.samplingIntervalDiagnosticsDataType
tdec["i=861"] = tdec.serverDiagnosticsSummaryDataType
tenc["i=861"] = tenc.serverDiagnosticsSummaryDataType
tdec["i=864"] = tdec.serverStatusDataType
tenc["i=864"] = tenc.serverStatusDataType
tdec["i=867"] = tdec.sessionDiagnosticsDataType
tenc["i=867"] = tenc.sessionDiagnosticsDataType
tdec["i=870"] = tdec.sessionSecurityDiagnosticsDataType
tenc["i=870"] = tenc.sessionSecurityDiagnosticsDataType
tdec["i=873"] = tdec.serviceCounterDataType
tenc["i=873"] = tenc.serviceCounterDataType
tdec["i=876"] = tdec.subscriptionDiagnosticsDataType
tenc["i=876"] = tenc.subscriptionDiagnosticsDataType
tdec["i=879"] = tdec.modelChangeStructureDataType
tenc["i=879"] = tenc.modelChangeStructureDataType
tdec["i=886"] = tdec.range
tenc["i=886"] = tenc.range
tdec["i=889"] = tdec.euinformation
tenc["i=889"] = tenc.euinformation
tdec["i=893"] = tdec.annotation
tenc["i=893"] = tenc.annotation
tdec["i=896"] = tdec.programDiagnosticDataType
tenc["i=896"] = tenc.programDiagnosticDataType
tdec["i=899"] = tdec.semanticChangeStructureDataType
tenc["i=899"] = tenc.semanticChangeStructureDataType
tdec["i=916"] = tdec.eventNotificationList
tenc["i=916"] = tenc.eventNotificationList
tdec["i=919"] = tdec.eventFieldList
tenc["i=919"] = tenc.eventFieldList
tdec["i=922"] = tdec.historyEventFieldList
tenc["i=922"] = tenc.historyEventFieldList
tdec["i=931"] = tdec.historyUpdateEventResult
tenc["i=931"] = tenc.historyUpdateEventResult
tdec["i=940"] = tdec.issuedIdentityToken
tenc["i=940"] = tenc.issuedIdentityToken
tdec["i=947"] = tdec.notificationData
tenc["i=947"] = tenc.notificationData
tdec["i=950"] = tdec.aggregateConfiguration
tenc["i=950"] = tenc.aggregateConfiguration
tdec["i=8251"] = tdec.enumValueType
tenc["i=8251"] = tenc.enumValueType
tdec["i=8917"] = tdec.timeZoneDataType
tenc["i=8917"] = tenc.timeZoneDataType
tdec["i=11226"] = tdec.modificationInfo
tenc["i=11226"] = tenc.modificationInfo
tdec["i=11227"] = tdec.historyModifiedData
tenc["i=11227"] = tenc.historyModifiedData
tdec["i=11300"] = tdec.updateStructureDataDetails
tenc["i=11300"] = tenc.updateStructureDataDetails
tdec["i=11889"] = tdec.instanceNode
tenc["i=11889"] = tenc.instanceNode
tdec["i=11890"] = tdec.typeNode
tenc["i=11890"] = tenc.typeNode
tdec["i=11957"] = tdec.endpointUrlListDataType
tenc["i=11957"] = tenc.endpointUrlListDataType
tdec["i=11958"] = tdec.networkGroupDataType
tenc["i=11958"] = tenc.networkGroupDataType
tdec["i=12089"] = tdec.axisInformation
tenc["i=12089"] = tenc.axisInformation
tdec["i=12090"] = tdec.xvtype
tenc["i=12090"] = tenc.xvtype
tdec["i=12181"] = tdec.complexNumberType
tenc["i=12181"] = tenc.complexNumberType
tdec["i=12182"] = tdec.doubleComplexNumberType
tenc["i=12182"] = tenc.doubleComplexNumberType
return a
