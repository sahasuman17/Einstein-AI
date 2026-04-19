/**
 * @description Controller for the caseCreate LWC supporting the
 * "Parts Technical Help" record type flow. Handles:
 *  - Asset lookup by Engine Serial Number (auto-populates product fields)
 *  - Type-ahead search across Part__c
 *  - Retrieval of a single Part by Id
 *  - Draft Case insert with record type resolved to 'Parts_Technical'
 *
 * All read methods are cacheable. All SOQL runs WITH USER_MODE;
 * all DML runs at AccessLevel.USER_MODE. LWC-facing errors are
 * surfaced as AuraHandledException.
 */
public with sharing class CaseCreateController {

    private static final String PARTS_TECHNICAL_DEV_NAME = 'Parts_Technical';
    private static final String CASE_DRAFT_STATUS        = 'Draft';
    private static final String TYPED_NO_MATCH_PREFIX    = 'Typed (no match): ';

    // ─── Asset lookup by Engine Serial Number ──────────────────────────────────

    /**
     * @description Finds an Asset by Engine_Serial_Number__c and returns
     * the product-information fields needed to auto-populate the form.
     * Returns an unmatched result (matched=false) when the serial is blank
     * or no Asset is found.
     *
     * @param serialNumber Engine Serial Number to match on Asset.Engine_Serial_Number__c
     * @return AssetMatchResult wrapper with match flag and populated fields.
     */
    @AuraEnabled(cacheable=true)
    public static AssetMatchResult findAssetBySerial(String serialNumber) {
        if (!Schema.sObjectType.Asset.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Asset records.');
        }

        AssetMatchResult result = new AssetMatchResult();
        result.matched = false;

        if (String.isBlank(serialNumber)) {
            return result;
        }

        String trimmed = serialNumber.trim();

        List<Asset> assets = [
            SELECT Id,
                   Engine_Serial_Number__c,
                   Machine_Type__c,
                   Series__c,
                   Model_Name__c,
                   Model_Name__r.Name,
                   Model_Name__r.Brand_Name__r.Name
            FROM Asset
            WHERE Engine_Serial_Number__c = :trimmed
            WITH USER_MODE
            LIMIT 1
        ];

        if (assets.isEmpty()) {
            return result;
        }

        Asset a = assets[0];
        result.matched      = true;
        result.assetId      = a.Id;
        result.machineType  = a.Machine_Type__c;
        result.series       = a.Series__c;
        result.engineSerial = a.Engine_Serial_Number__c;
        result.modelNumber  = (a.Model_Name__r != null) ? a.Model_Name__r.Name : null;
        result.brand        = (a.Model_Name__r != null && a.Model_Name__r.Brand_Name__r != null)
                                ? a.Model_Name__r.Brand_Name__r.Name
                                : null;
        return result;
    }

    // ─── Part type-ahead search ────────────────────────────────────────────────

    /**
     * @description Returns up to 20 Part__c records whose Name contains the
     * supplied search term (case-insensitive LIKE). Returns an empty list
     * if the term is blank or shorter than 2 characters. SOQL wildcards in
     * the input ('%', '_') are escaped so user input cannot broaden the
     * search.
     *
     * @param searchTerm User-typed fragment of the part number.
     * @return List of PartResult matching the term.
     */
    @AuraEnabled(cacheable=true)
    public static List<PartResult> searchParts(String searchTerm) {
        if (!Schema.sObjectType.Part__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Part records.');
        }

        List<PartResult> results = new List<PartResult>();

        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return results;
        }

        // Escape SOQL LIKE wildcards so typed '%' / '_' do not broaden the match.
        String sanitized = searchTerm.trim()
                                     .replace('\\', '\\\\')
                                     .replace('%', '\\%')
                                     .replace('_', '\\_');
        String likeTerm = '%' + sanitized + '%';

        List<Part__c> parts = [
            SELECT Id, Name, Part_Description__c
            FROM Part__c
            WHERE Name LIKE :likeTerm
            WITH USER_MODE
            ORDER BY Name
            LIMIT 20
        ];

        for (Part__c p : parts) {
            PartResult pr   = new PartResult();
            pr.id           = p.Id;
            pr.name         = p.Name;
            pr.description  = p.Part_Description__c;
            results.add(pr);
        }
        return results;
    }

    /**
     * @description Returns a single Part__c by Id. Used when the LWC
     * needs to re-fetch description details for a previously selected Part.
     *
     * @param partId Id of the Part__c record.
     * @return PartResult populated from the matched Part.
     */
    @AuraEnabled(cacheable=true)
    public static PartResult getPartById(Id partId) {
        if (!Schema.sObjectType.Part__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Part records.');
        }

        List<Part__c> parts = [
            SELECT Id, Name, Part_Description__c
            FROM Part__c
            WHERE Id = :partId
            WITH USER_MODE
            LIMIT 1
        ];

        if (parts.isEmpty()) {
            throw new AuraHandledException('Part not found or inaccessible.');
        }

        Part__c p      = parts[0];
        PartResult pr  = new PartResult();
        pr.id          = p.Id;
        pr.name        = p.Name;
        pr.description = p.Part_Description__c;
        return pr;
    }

    // ─── Draft Case insert ─────────────────────────────────────────────────────

    /**
     * @description Inserts a new Case in 'Draft' status with the
     * Parts_Technical record type. Mandatory product-information fields
     * are validated server-side; any missing ones trigger an
     * AuraHandledException listing them.
     *
     * AC-6: When partId is null and partNumberText was typed, the typed
     * string is stored in Case.Part_Description__c prefixed with
     * 'Typed (no match): ' so reviewers can tell it is a free-text value
     * with no matching Part__c record.
     *
     * @param input Wrapper carrying all product-information fields from the LWC.
     * @return Id of the newly inserted Case.
     */
    @AuraEnabled
    public static Id saveCaseAsDraft(CaseDraftInput input) {
        if (input == null) {
            throw new AuraHandledException('No case data was supplied.');
        }

        // Validate required product-information fields.
        List<String> missing = new List<String>();
        if (String.isBlank(input.assetSerialNumber)) missing.add('Asset/Serial Number');
        if (String.isBlank(input.brand))             missing.add('Brand');
        if (String.isBlank(input.machineType))       missing.add('Machine Type');
        if (String.isBlank(input.series))            missing.add('Series');
        if (String.isBlank(input.modelNumber))       missing.add('Model Number');

        if (!missing.isEmpty()) {
            throw new AuraHandledException(
                'Missing required fields: ' + String.join(missing, ', ')
            );
        }

        // Resolve the Parts_Technical record type.
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
              AND DeveloperName = :PARTS_TECHNICAL_DEV_NAME
            LIMIT 1
        ];
        if (rts.isEmpty()) {
            throw new AuraHandledException(
                'Parts Technical Help record type is not available for Case.'
            );
        }

        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Case records.');
        }

        // AC-6: store the typed part number as a description prefix when
        // no matching Part__c was selected. Otherwise use the description
        // that the LWC derived from the selected Part record.
        String partDescToSave;
        if (input.partId == null && String.isNotBlank(input.partNumberText)) {
            partDescToSave = TYPED_NO_MATCH_PREFIX + input.partNumberText.trim();
        } else {
            partDescToSave = input.partDescription;
        }

        Case c = new Case(
            Status                = CASE_DRAFT_STATUS,
            RecordTypeId          = rts[0].Id,
            Part_Number__c        = input.partId,
            Part_Description__c   = partDescToSave,
            No_Causal_Part_Reason__c = input.noPartReason,
            Used_With__c          = input.usedWith
        );

        Database.insert(c, AccessLevel.USER_MODE);
        return c.Id;
    }

    // ─── Inner wrapper classes ─────────────────────────────────────────────────

    public class AssetMatchResult {
        @AuraEnabled public Boolean matched;
        @AuraEnabled public Id     assetId;
        @AuraEnabled public String brand;
        @AuraEnabled public String machineType;
        @AuraEnabled public String series;
        @AuraEnabled public String modelNumber;
        @AuraEnabled public String engineSerial;
    }

    public class PartResult {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
    }

    public class CaseDraftInput {
        @AuraEnabled public String assetSerialNumber;
        @AuraEnabled public String brand;
        @AuraEnabled public String machineType;
        @AuraEnabled public String series;
        @AuraEnabled public String modelNumber;
        @AuraEnabled public String engineSerial;
        @AuraEnabled public Id     partId;
        @AuraEnabled public String partNumberText;
        @AuraEnabled public String partDescription;
        @AuraEnabled public String noPartReason;
        @AuraEnabled public String usedWith;
    }
}