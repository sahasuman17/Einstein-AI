/**
 * @description Test class for CaseCreateController (MP-4).
 *              Covers getProductInfoFromAsset, getPartDescription,
 *              saveCaseAsDraft, and submitCase.
 * @author Unit Testing Agent
 */
@isTest
private class CaseCreateControllerTest {

    // ─────────────────────────────────────────────────────────────────────────────
    // Test Data Setup
    // ─────────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        // Brand → Model → Asset hierarchy
        Brand__c brand = new Brand__c(Name = 'TestBrand', Brand_Code__c = 'TB01');
        insert brand;

        Model__c model = new Model__c(Name = 'TestModel', Brand_Name__c = brand.Id);
        insert model;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Product2 prod = new Product2(
            Name        = 'Test Product',
            IsActive    = true,
            Type__c     = 'Tractors',
            Series__c   = 'T-Series'
        );
        insert prod;

        Asset asset = new Asset(
            Name                    = 'ASSET-001',
            AccountId               = acc.Id,
            Product2Id              = prod.Id,
            SerialNumber            = 'SN-TEST-001',
            Model_Name__c           = model.Id,
            Unit_of_Measure__c      = 'Hours',
            Usage__c                = 1500,
            Engine_Serial_Number__c = 'ENG-001'
        );
        insert asset;

        Part__c part = new Part__c(
            Name                = 'P-001',
            Part_Description__c = 'Hydraulic Filter'
        );
        insert part;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Helper: retrieve shared test records by field value
    // ─────────────────────────────────────────────────────────────────────────────

    private static Asset getTestAsset() {
        return [SELECT Id, Name, SerialNumber FROM Asset WHERE Name = 'ASSET-001' LIMIT 1];
    }

    private static Part__c getTestPart() {
        return [SELECT Id, Part_Description__c FROM Part__c WHERE Name = 'P-001' LIMIT 1];
    }

    // =========================================================================
    // getProductInfoFromAsset — blank / null input
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_blankInput_returnsNull() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('');
        Test.stopTest();

        Assert.isNull(result, 'Blank serial number should return null');
    }

    @isTest
    static void testGetProductInfoFromAsset_nullInput_returnsNull() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset(null);
        Test.stopTest();

        Assert.isNull(result, 'Null serial number should return null');
    }

    @isTest
    static void testGetProductInfoFromAsset_whitespaceInput_returnsNull() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('   ');
        Test.stopTest();

        Assert.isNull(result, 'Whitespace-only serial number should return null');
    }

    // =========================================================================
    // getProductInfoFromAsset — SerialNumber match
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_bySerialNumber_returnsWrapper() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('SN-TEST-001');
        Test.stopTest();

        Assert.isNotNull(result, 'Should return a wrapper when SerialNumber matches');
        Assert.areEqual('TestBrand',  result.brand,           'Brand should match');
        Assert.areEqual('Tractors',   result.machineType,     'Machine type should match');
        Assert.areEqual('T-Series',   result.series,          'Series should match');
        Assert.areEqual('TestModel',  result.modelNumber,     'Model number should match');
        Assert.areEqual('Hours',      result.unitOfMeasure,   'Unit of measure should match');
        Assert.isTrue(result.usageAvailable,                  'Usage should be available');
        Assert.areEqual('1500',       result.machineUsage,    'Machine usage should be 1500');
        Assert.areEqual('ENG-001',    result.engineSerial,    'Engine serial should match');
        Assert.isNotNull(result.assetId,                      'Asset Id should be populated');
    }

    // =========================================================================
    // getProductInfoFromAsset — Name match
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_byName_returnsWrapper() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('ASSET-001');
        Test.stopTest();

        Assert.isNotNull(result, 'Should return a wrapper when Name matches');
        Assert.isNotNull(result.assetId, 'Asset Id should be populated on name match');
    }

    // =========================================================================
    // getProductInfoFromAsset — Id match
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_byId_returnsWrapper() {
        Asset asset = getTestAsset();

        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset(asset.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Should return a wrapper when Asset Id matches');
        Assert.areEqual(asset.Id, result.assetId, 'Returned assetId should match the queried Asset');
    }

    // =========================================================================
    // getProductInfoFromAsset — no match
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_noMatch_returnsNull() {
        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('DOES-NOT-EXIST-XYZ');
        Test.stopTest();

        Assert.isNull(result, 'Non-matching input should return null');
    }

    // =========================================================================
    // getProductInfoFromAsset — asset without Model/Brand (null-safe paths)
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_noModelNoBrand_returnsNullBrand() {
        Account acc = new Account(Name = 'Bare Account');
        insert acc;

        Asset bareAsset = new Asset(
            Name      = 'BARE-ASSET',
            AccountId = acc.Id
        );
        insert bareAsset;

        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('BARE-ASSET');
        Test.stopTest();

        Assert.isNotNull(result,    'Should still return a wrapper for bare asset');
        Assert.isNull(result.brand, 'Brand should be null when no Model/Brand relationship exists');
        Assert.isNull(result.machineType, 'Machine type should be null when no Product2 exists');
        Assert.isNull(result.series,      'Series should be null when no Product2 exists');
        Assert.isFalse(result.usageAvailable, 'usageAvailable should be false when Usage__c is null');
        Assert.isNull(result.machineUsage,    'Machine usage should be null when Usage__c is null');
    }

    // =========================================================================
    // getProductInfoFromAsset — asset with Model but no Brand
    // =========================================================================

    @isTest
    static void testGetProductInfoFromAsset_modelWithoutBrand_returnsNullBrand() {
        Account acc = new Account(Name = 'NoBrand Account');
        insert acc;

        Model__c modelNoBrand = new Model__c(Name = 'NoBrandModel');
        insert modelNoBrand;

        Asset asset = new Asset(
            Name          = 'NOBRAND-ASSET',
            AccountId     = acc.Id,
            Model_Name__c = modelNoBrand.Id
        );
        insert asset;

        Test.startTest();
        CaseCreateController.ProductInfoWrapper result =
            CaseCreateController.getProductInfoFromAsset('NOBRAND-ASSET');
        Test.stopTest();

        Assert.isNotNull(result,    'Wrapper should be returned');
        Assert.isNull(result.brand, 'Brand should be null when model has no Brand_Name__c');
        Assert.areEqual('NoBrandModel', result.modelNumber, 'Model number should still be populated');
    }

    // =========================================================================
    // getPartDescription — null partId
    // =========================================================================

    @isTest
    static void testGetPartDescription_nullPartId_returnsNull() {
        Test.startTest();
        String result = CaseCreateController.getPartDescription(null);
        Test.stopTest();

        Assert.isNull(result, 'Null partId should return null without querying');
    }

    // =========================================================================
    // getPartDescription — valid partId
    // =========================================================================

    @isTest
    static void testGetPartDescription_validPartId_returnsDescription() {
        Part__c part = getTestPart();

        Test.startTest();
        String result = CaseCreateController.getPartDescription(part.Id);
        Test.stopTest();

        Assert.areEqual('Hydraulic Filter', result,
            'Should return the Part_Description__c value for a valid Id');
    }

    // =========================================================================
    // getPartDescription — no match (deleted record)
    // =========================================================================

    @isTest
    static void testGetPartDescription_noMatch_returnsNull() {
        Part__c part = getTestPart();
        Id partId    = part.Id;
        delete part;

        Test.startTest();
        String result = CaseCreateController.getPartDescription(partId);
        Test.stopTest();

        Assert.isNull(result, 'Deleted Part should result in null return (empty list path)');
    }

    // =========================================================================
    // saveCaseAsDraft — null caseRecord throws
    // =========================================================================

    @isTest
    static void testSaveCaseAsDraft_nullCase_throwsAuraHandledException() {
        Test.startTest();
        try {
            CaseCreateController.saveCaseAsDraft(null);
            Assert.fail('Expected AuraHandledException was not thrown for null Case');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Case record is required'),
                'Exception message should state that Case record is required'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // saveCaseAsDraft — valid new Case (insert path)
    // =========================================================================

    @isTest
    static void testSaveCaseAsDraft_newCase_insertsAndReturnsId() {
        Case newCase = new Case(Subject = 'Test Draft Case');

        Test.startTest();
        Id returnedId = CaseCreateController.saveCaseAsDraft(newCase);
        Test.stopTest();

        Assert.isNotNull(returnedId, 'saveCaseAsDraft should return a non-null Id');

        Case saved = [SELECT Id, Status, Subject FROM Case WHERE Id = :returnedId LIMIT 1];
        Assert.areEqual('Draft',          saved.Status,  'Status must be set to Draft');
        Assert.areEqual('Test Draft Case', saved.Subject, 'Subject should be persisted');
    }

    // =========================================================================
    // saveCaseAsDraft — existing Case (update path)
    // =========================================================================

    @isTest
    static void testSaveCaseAsDraft_existingCase_updatesRecord() {
        Case existingCase = new Case(Subject = 'Original Subject', Status = 'Draft');
        insert existingCase;

        existingCase.Subject = 'Updated Subject';

        Test.startTest();
        Id returnedId = CaseCreateController.saveCaseAsDraft(existingCase);
        Test.stopTest();

        Assert.areEqual(existingCase.Id, returnedId, 'Returned Id should match existing Case Id');

        Case updated = [SELECT Id, Subject, Status FROM Case WHERE Id = :existingCase.Id LIMIT 1];
        Assert.areEqual('Updated Subject', updated.Subject, 'Subject should be updated');
        Assert.areEqual('Draft',           updated.Status,  'Status should remain Draft after update');
    }

    // =========================================================================
    // saveCaseAsDraft — Status is forced to Draft regardless of input
    // =========================================================================

    @isTest
    static void testSaveCaseAsDraft_statusAlwaysSetToDraft() {
        Case newCase = new Case(Subject = 'Status Override Test');

        Test.startTest();
        Id returnedId = CaseCreateController.saveCaseAsDraft(newCase);
        Test.stopTest();

        Case saved = [SELECT Status FROM Case WHERE Id = :returnedId LIMIT 1];
        Assert.areEqual('Draft', saved.Status,
            'saveCaseAsDraft must always force Status to Draft');
    }

    // =========================================================================
    // submitCase — null caseId throws
    // =========================================================================

    @isTest
    static void testSubmitCase_nullCaseId_throwsAuraHandledException() {
        Test.startTest();
        try {
            CaseCreateController.submitCase(null);
            Assert.fail('Expected AuraHandledException was not thrown for null caseId');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Case Id is required'),
                'Exception message should mention Case Id is required'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — happy path: all required fields present
    // =========================================================================

    @isTest
    static void testSubmitCase_allRequiredFields_submitsSuccessfully() {
        Asset asset = getTestAsset();

        Case draftCase = new Case(
            AssetId     = asset.Id,
            Priority    = 'Medium',
            Severity__c = 'C-Nuisance',
            Description = 'Machine makes clicking noise',
            Status      = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        Id returnedId = CaseCreateController.submitCase(draftCase.Id);
        Test.stopTest();

        Assert.areEqual(draftCase.Id, returnedId, 'Returned Id should match the submitted Case Id');

        Case submitted = [SELECT Id, Status FROM Case WHERE Id = :draftCase.Id LIMIT 1];
        Assert.areEqual('Submitted', submitted.Status,
            'Status should be Submitted after successful submitCase call');
    }

    // =========================================================================
    // submitCase — missing AssetId throws
    // =========================================================================

    @isTest
    static void testSubmitCase_missingAssetId_throwsWithMissingField() {
        Case draftCase = new Case(
            Priority    = 'High',
            Severity__c = 'A-Machine Immobilized',
            Description = 'Tractor will not start',
            Status      = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(draftCase.Id);
            Assert.fail('Expected AuraHandledException for missing AssetId');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Asset/Serial Number'),
                'Exception message should mention Asset/Serial Number as a missing field'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — missing Priority throws
    // =========================================================================

    @isTest
    static void testSubmitCase_missingPriority_throwsWithMissingField() {
        Asset asset = getTestAsset();

        Case draftCase = new Case(
            AssetId     = asset.Id,
            Severity__c = 'B-Impaired Functionality',
            Description = 'Loss of power steering',
            Status      = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(draftCase.Id);
            Assert.fail('Expected AuraHandledException for missing Priority');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Priority'),
                'Exception message should mention Priority as a missing field'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — missing Severity__c throws
    // =========================================================================

    @isTest
    static void testSubmitCase_missingSeverity_throwsWithMissingField() {
        Asset asset = getTestAsset();

        Case draftCase = new Case(
            AssetId     = asset.Id,
            Priority    = 'Low',
            Description = 'Minor oil leak',
            Status      = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(draftCase.Id);
            Assert.fail('Expected AuraHandledException for missing Severity__c');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Severity'),
                'Exception message should mention Severity as a missing field'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — missing Description throws
    // =========================================================================

    @isTest
    static void testSubmitCase_missingDescription_throwsWithMissingField() {
        Asset asset = getTestAsset();

        Case draftCase = new Case(
            AssetId     = asset.Id,
            Priority    = 'Medium',
            Severity__c = 'C-Nuisance',
            Status      = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(draftCase.Id);
            Assert.fail('Expected AuraHandledException for missing Description');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Problem Description'),
                'Exception message should mention Problem Description as a missing field'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — multiple missing fields: message lists all of them
    // =========================================================================

    @isTest
    static void testSubmitCase_multipleMissingFields_messageListsAll() {
        Case draftCase = new Case(
            Subject = 'Incomplete Case',
            Status  = 'Draft'
        );
        insert draftCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(draftCase.Id);
            Assert.fail('Expected AuraHandledException for multiple missing fields');
        } catch (AuraHandledException e) {
            String msg = e.getMessage();
            Assert.isTrue(
                msg.contains('Asset/Serial Number'),
                'Exception should list Asset/Serial Number as missing'
            );
            Assert.isTrue(
                msg.contains('Priority'),
                'Exception should list Priority as missing'
            );
            Assert.isTrue(
                msg.contains('Severity'),
                'Exception should list Severity as missing'
            );
            Assert.isTrue(
                msg.contains('Problem Description'),
                'Exception should list Problem Description as missing'
            );
            Assert.isTrue(
                msg.contains('Cannot submit Case'),
                'Exception should include the cannot-submit preamble'
            );
        }
        Test.stopTest();
    }

    // =========================================================================
    // submitCase — Case not found throws
    // =========================================================================

    @isTest
    static void testSubmitCase_caseNotFound_throwsAuraHandledException() {
        Case tempCase = new Case(Subject = 'Temp', Status = 'Draft');
        insert tempCase;
        Id staleId = tempCase.Id;
        delete tempCase;

        Test.startTest();
        try {
            CaseCreateController.submitCase(staleId);
            Assert.fail('Expected AuraHandledException for deleted Case');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Case not found'),
                'Exception message should state Case not found'
            );
        }
        Test.stopTest();
    }
}