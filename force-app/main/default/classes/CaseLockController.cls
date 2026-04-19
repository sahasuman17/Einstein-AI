public with sharing class CaseLockController {

    private static final Set<String> LOCKED_STATUSES = new Set<String>{ 'Closed', 'Resolved' };

    // ─── Case lock state ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static CaseData getCaseData(Id caseId) {
        if (!Schema.sObjectType.Case.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Case records.');
        }

        List<Case> cases = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            throw new AuraHandledException('Case not found or access denied.');
        }

        String status = cases[0].Status;
        CaseData result = new CaseData();
        result.isLocked       = LOCKED_STATUSES.contains(status);
        result.isCancelHidden = status == 'New';
        result.status         = status;
        return result;
    }

    // ─── Comments (read-only) ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CommentInfo> getCaseComments(Id caseId) {
        if (!Schema.sObjectType.CaseComment.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Case Comments.');
        }

        List<CaseComment> rawComments = [
            SELECT Id, CommentBody, CreatedDate, CreatedBy.Name, IsPublished
            FROM CaseComment
            WHERE ParentId = :caseId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        List<CommentInfo> result = new List<CommentInfo>();
        for (CaseComment c : rawComments) {
            CommentInfo info    = new CommentInfo();
            info.id             = c.Id;
            info.commentBody    = c.CommentBody;
            info.createdDate    = c.CreatedDate;
            info.createdByName  = c.CreatedBy.Name;
            info.isPublished    = c.IsPublished;
            result.add(info);
        }
        return result;
    }

    // ─── Attachments (read-only) ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AttachmentInfo> getCaseAttachments(Id caseId) {
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Attachments.');
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.ContentSize,
                   ContentDocument.LastModifiedDate,
                   ContentDocument.LastModifiedBy.Name
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
            WITH USER_MODE
            ORDER BY ContentDocument.LastModifiedDate DESC
            LIMIT 50
        ];

        List<AttachmentInfo> result = new List<AttachmentInfo>();
        for (ContentDocumentLink link : links) {
            AttachmentInfo info    = new AttachmentInfo();
            info.documentId        = link.ContentDocumentId;
            info.title             = link.ContentDocument.Title;
            info.fileType          = link.ContentDocument.FileType;
            info.contentSize       = link.ContentDocument.ContentSize;
            info.lastModifiedDate  = link.ContentDocument.LastModifiedDate;
            info.lastModifiedBy    = link.ContentDocument.LastModifiedBy.Name;
            result.add(info);
        }
        return result;
    }

    // ─── Feedback submission ────────────────────────────────────────────────────

    @AuraEnabled
    public static void submitFeedback(Id caseId, String feedbackText) {
        if (String.isBlank(feedbackText)) {
            throw new AuraHandledException('Feedback text cannot be empty.');
        }
        if (feedbackText.trim().length() > 32000) {
            throw new AuraHandledException('Feedback text exceeds the maximum allowed length.');
        }

        // Re-verify case status — reject feedback on non-locked cases
        List<Case> cases = [
            SELECT Id, Status FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Case not found or access denied.');
        }
        if (!LOCKED_STATUSES.contains(cases[0].Status)) {
            throw new AuraHandledException('Feedback can only be submitted on Closed or Resolved cases.');
        }

        if (!Schema.sObjectType.CaseComment.isCreateable() ||
            !Schema.sObjectType.CaseComment.fields.CommentBody.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to submit feedback.');
        }

        CaseComment feedback = new CaseComment(
            ParentId    = caseId,
            CommentBody = '[Feedback] ' + feedbackText.trim(),
            IsPublished = true
        );
        Database.insert(feedback, AccessLevel.USER_MODE);
    }

    // ─── Inner wrapper classes ──────────────────────────────────────────────────

    public class CaseData {
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public Boolean isCancelHidden;
        @AuraEnabled public String  status;
    }

    public class CommentInfo {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   commentBody;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String   createdByName;
        @AuraEnabled public Boolean  isPublished;
    }

    public class AttachmentInfo {
        @AuraEnabled public Id       documentId;
        @AuraEnabled public String   title;
        @AuraEnabled public String   fileType;
        @AuraEnabled public Integer  contentSize;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String   lastModifiedBy;
    }
}