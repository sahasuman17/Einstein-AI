import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getCaseData from '@salesforce/apex/CaseLockController.getCaseData';
import getCaseComments from '@salesforce/apex/CaseLockController.getCaseComments';
import getCaseAttachments from '@salesforce/apex/CaseLockController.getCaseAttachments';
import submitFeedback from '@salesforce/apex/CaseLockController.submitFeedback';

const ATTACHMENT_COLUMNS = [
    { label: 'File Name',     fieldName: 'title',            type: 'text'   },
    { label: 'Type',          fieldName: 'fileType',         type: 'text'   },
    { label: 'Size (bytes)',  fieldName: 'contentSize',      type: 'number' },
    { label: 'Last Modified', fieldName: 'lastModifiedDate', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }   },
    { label: 'Modified By',   fieldName: 'lastModifiedBy',   type: 'text'   }
];

export default class CaseLock extends LightningElement {
    @api recordId;

    @track feedbackText = '';
    @track isFeedbackSubmitting = false;

    _caseDataResult;
    _commentsResult;
    _attachmentsResult;

    // ─── Wire adapters ────────────────────────────────────────────────────────

    @wire(getCaseData, { caseId: '$recordId' })
    wiredCaseData(result) {
        this._caseDataResult = result;
    }

    @wire(getCaseComments, { caseId: '$recordId' })
    wiredComments(result) {
        this._commentsResult = result;
    }

    @wire(getCaseAttachments, { caseId: '$recordId' })
    wiredAttachments(result) {
        this._attachmentsResult = result;
    }

    // ─── Loading / error / ready states ──────────────────────────────────────

    get isLoading() {
        return !this._caseDataResult?.data && !this._caseDataResult?.error;
    }

    get hasError() {
        return !!this._caseDataResult?.error;
    }

    get errorMessage() {
        return this._caseDataResult?.error?.body?.message ?? 'An unexpected error occurred.';
    }

    // ─── Lock state ───────────────────────────────────────────────────────────

    get isLocked() {
        return this._caseDataResult?.data?.isLocked === true;
    }

    get caseStatus() {
        return this._caseDataResult?.data?.status ?? '';
    }

    /**
     * Cancel button is shown for all statuses EXCEPT 'New'.
     * When a case is New, cancelling would discard mandatory information.
     */
    get showCancelButton() {
        return !this._caseDataResult?.data?.isCancelHidden;
    }

    // ─── Comments ─────────────────────────────────────────────────────────────

    get comments() {
        return this._commentsResult?.data ?? [];
    }

    get hasComments() {
        return this.comments.length > 0;
    }

    // ─── Attachments ──────────────────────────────────────────────────────────

    get attachments() {
        return this._attachmentsResult?.data ?? [];
    }

    get hasAttachments() {
        return this.attachments.length > 0;
    }

    get attachmentColumns() {
        return ATTACHMENT_COLUMNS;
    }

    // ─── Edit form handlers ───────────────────────────────────────────────────

    handleSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title:   'Saved',
            message: 'Case updated successfully.',
            variant: 'success'
        }));
        // Re-evaluate lock state in case status changed to Closed/Resolved
        refreshApex(this._caseDataResult);
    }

    handleFormError(event) {
        this.dispatchEvent(new ShowToastEvent({
            title:   'Save Failed',
            message: event.detail?.message ?? 'An error occurred while saving the case.',
            variant: 'error'
        }));
    }

    /**
     * Resets all input fields to their last-saved values.
     * Called only when the cancel button is visible (status !== 'New').
     */
    handleCancel() {
        this.template.querySelectorAll('lightning-input-field').forEach(field => field.reset());
    }

    // ─── Feedback handlers ────────────────────────────────────────────────────

    handleFeedbackChange(event) {
        this.feedbackText = event.detail.value;
    }

    handleFeedbackSubmit() {
        const text = this.feedbackText?.trim();
        if (!text) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Validation Error',
                message: 'Please enter feedback text before submitting.',
                variant: 'error',
                mode:    'sticky'
            }));
            return;
        }

        this.isFeedbackSubmitting = true;

        submitFeedback({ caseId: this.recordId, feedbackText: text })
            .then(() => {
                this.feedbackText = '';
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Feedback Submitted',
                    message: 'Thank you. Your feedback has been recorded on the case.',
                    variant: 'success'
                }));
                return refreshApex(this._commentsResult);
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Submission Failed',
                    message: error?.body?.message ?? 'Unable to submit feedback. Please try again.',
                    variant: 'error',
                    mode:    'sticky'
                }));
            })
            .finally(() => {
                this.isFeedbackSubmitting = false;
            });
    }
}