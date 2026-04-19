import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import findAssetBySerial from '@salesforce/apex/CaseCreateController.findAssetBySerial';
import searchParts from '@salesforce/apex/CaseCreateController.searchParts';
import getPartById from '@salesforce/apex/CaseCreateController.getPartById';
import saveCaseAsDraft from '@salesforce/apex/CaseCreateController.saveCaseAsDraft';

const PART_SEARCH_DEBOUNCE_MS = 300;
const PART_BLUR_HIDE_MS = 150;

export default class CaseCreate extends LightningElement {
    /* ---------- section toggle state ---------- */
    assetOpen = true;
    productOpen = true;
    caseInfoOpen = true;
    commentsOpen = true;
    dealerOpen = true;
    attachmentsOpen = true;
    resolveOpen = true;

    /* ---------- out-of-scope field state ---------- */
    assetNotApplicable = false;
    requestCallback = true;

    /* ---------- Asset/Serial + Product Information state (MP-7) ---------- */
    assetSerialNumber = '';
    brand = '';
    machineType = '';
    series = '';
    modelNumber = '';
    engineSerial = '';
    partId = null;
    partNumberText = '';
    partDescription = '';
    noPartReason = '';
    usedWith = '';
    unitOfMeasure = '';
    machineUsage = '';

    /* ---------- Asset match + part search UI state ---------- */
    assetMatchState = ''; // '', 'found', 'notfound'
    partResults = [];
    partResultsVisible = false;
    saving = false;

    /* ---------- Internal timers ---------- */
    _partSearchTimer;
    _partBlurTimer;

    /* ---------- static attachment list ---------- */
    dummyFiles = [
        { id: '1', name: 'Filename.png' },
        { id: '2', name: 'Filename.png' },
        { id: '3', name: 'Filename.png' },
        { id: '4', name: 'Filename.png' },
        { id: '5', name: 'Filename.png' }
    ];

    get fileCount() {
        return this.dummyFiles.length;
    }

    /* ---------- chevron icons ---------- */
    get assetChevron() {
        return this.assetOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get productChevron() {
        return this.productOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get caseInfoChevron() {
        return this.caseInfoOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get commentsChevron() {
        return this.commentsOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get dealerChevron() {
        return this.dealerOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get attachmentsChevron() {
        return this.attachmentsOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get resolveChevron() {
        return this.resolveOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    /* ---------- section toggle ---------- */
    toggleSection(event) {
        const section = event.currentTarget.dataset.section;
        const prop = section + 'Open';
        this[prop] = !this[prop];
    }

    handleAssetToggle(event) {
        this.assetNotApplicable = event.target.checked;
    }

    /* ---------- Asset/Serial Number handlers (MP-7) ---------- */
    handleAssetSerialChange(event) {
        this.assetSerialNumber = event.target.value;
        // Clear any prior match banner as soon as the user edits the serial.
        this.assetMatchState = '';
    }

    handleAssetKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleAssetSearch();
        }
    }

    handleAssetSearch() {
        const serial = (this.assetSerialNumber || '').trim();
        if (!serial) {
            this.assetMatchState = 'notfound';
            return;
        }
        findAssetBySerial({ serialNumber: serial })
            .then((res) => {
                if (res && res.matched) {
                    this.brand = res.brand || '';
                    this.machineType = res.machineType || '';
                    this.series = res.series || '';
                    this.modelNumber = res.modelNumber || '';
                    this.engineSerial = res.engineSerial || '';
                    this.assetMatchState = 'found';
                } else {
                    // Not found — clear auto-populated product fields.
                    this.brand = '';
                    this.machineType = '';
                    this.series = '';
                    this.modelNumber = '';
                    this.engineSerial = '';
                    this.assetMatchState = 'notfound';
                }
            })
            .catch((err) => {
                this.assetMatchState = 'notfound';
                this.showToast('Error', this.reduceError(err), 'error');
            });
    }

    handleClearSearch() {
        this.assetSerialNumber = '';
        this.brand = '';
        this.machineType = '';
        this.series = '';
        this.modelNumber = '';
        this.engineSerial = '';
        this.assetMatchState = '';
    }

    /* ---------- Product Information simple field handlers ---------- */
    handleBrandChange(event) {
        this.brand = event.target.value;
    }
    handleMachineTypeChange(event) {
        this.machineType = event.target.value;
    }
    handleSeriesChange(event) {
        this.series = event.target.value;
    }
    handleModelNumberChange(event) {
        this.modelNumber = event.target.value;
    }
    handleEngineSerialChange(event) {
        this.engineSerial = event.target.value;
    }
    handleUsedWithChange(event) {
        this.usedWith = event.target.value;
    }
    handleUnitOfMeasureChange(event) {
        this.unitOfMeasure = event.target.value;
    }
    handleMachineUsageChange(event) {
        this.machineUsage = event.target.value;
    }
    handleNoPartReasonChange(event) {
        this.noPartReason = event.target.value;
    }

    /* ---------- Part Number search lookup (MP-7) ---------- */
    handlePartInput(event) {
        const term = event.target.value;
        this.partNumberText = term;
        // User edited the text → selection no longer binds to a stored Part.
        this.partId = null;
        this.partDescription = '';

        // Debounced server call.
        if (this._partSearchTimer) {
            clearTimeout(this._partSearchTimer);
        }
        this._partSearchTimer = setTimeout(() => {
            if (!term || term.trim().length < 2) {
                this.partResults = [];
                this.partResultsVisible = false;
                return;
            }
            searchParts({ searchTerm: term })
                .then((results) => {
                    this.partResults = results || [];
                    this.partResultsVisible = this.partResults.length > 0;
                })
                .catch((err) => {
                    this.partResults = [];
                    this.partResultsVisible = false;
                    this.showToast('Error', this.reduceError(err), 'error');
                });
        }, PART_SEARCH_DEBOUNCE_MS);
    }

    handlePartSelect(event) {
        const selectedId = event.currentTarget.dataset.id;
        const match = this.partResults.find((p) => p.id === selectedId);
        if (match) {
            this.partId = match.id;
            this.partNumberText = match.name;
            this.partDescription = match.description || '';
        }
        this.partResults = [];
        this.partResultsVisible = false;
    }

    handlePartBlur() {
        // Delay hiding so a click on a dropdown item can still register.
        if (this._partBlurTimer) {
            clearTimeout(this._partBlurTimer);
        }
        this._partBlurTimer = setTimeout(() => {
            this.partResultsVisible = false;
            // AC-6: if no selection was made, the typed string remains in the
            // input and is submitted as a 'Typed (no match): …' description.
        }, PART_BLUR_HIDE_MS);
    }

    handlePartFocus() {
        if (this.partResults && this.partResults.length > 0) {
            this.partResultsVisible = true;
        }
    }

    /* ---------- Optionally fetch a Part by id (not auto-wired but available) ---------- */
    refreshPartFromServer(partId) {
        return getPartById({ partId })
            .then((p) => {
                if (p) {
                    this.partId = p.id;
                    this.partNumberText = p.name;
                    this.partDescription = p.description || '';
                }
            })
            .catch((err) => {
                this.showToast('Error', this.reduceError(err), 'error');
            });
    }

    /* ---------- Save (MP-7) ---------- */
    handleSave() {
        const missing = [];
        if (!this.assetSerialNumber || !this.assetSerialNumber.trim()) missing.push('Asset/Serial Number');
        if (!this.brand)        missing.push('Brand');
        if (!this.machineType)  missing.push('Machine Type');
        if (!this.series)       missing.push('Series');
        if (!this.modelNumber)  missing.push('Model Number');

        if (missing.length > 0) {
            this.showToast(
                'Missing required information',
                'Please complete: ' + missing.join(', '),
                'error'
            );
            return;
        }

        const input = {
            assetSerialNumber: this.assetSerialNumber,
            brand:             this.brand,
            machineType:       this.machineType,
            series:            this.series,
            modelNumber:       this.modelNumber,
            engineSerial:      this.engineSerial,
            partId:            this.partId,
            partNumberText:    this.partNumberText,
            partDescription:   this.partDescription,
            noPartReason:      this.noPartReason,
            usedWith:          this.usedWith
        };

        this.saving = true;
        saveCaseAsDraft({ input })
            .then(() => {
                this.showToast('Success', 'Case saved as Draft', 'success');
            })
            .catch((err) => {
                this.showToast('Error', this.reduceError(err), 'error');
            })
            .finally(() => {
                this.saving = false;
            });
    }

    /* ---------- Derived getters ---------- */
    get assetMatchFound() {
        return this.assetMatchState === 'found';
    }

    get assetMatchNotFound() {
        return this.assetMatchState === 'notfound';
    }

    get hasPartResults() {
        return this.partResultsVisible && this.partResults && this.partResults.length > 0;
    }

    get isSaveDisabled() {
        return this.saving;
    }

    /* ---------- Combobox options ---------- */
    get unitOptions() {
        return [
            { label: 'Hours', value: 'Hours' },
            { label: 'Miles', value: 'Miles' },
            { label: 'Kilometers', value: 'Kilometers' }
        ];
    }

    get usageOptions() {
        return [
            { label: '0-500', value: '0-500' },
            { label: '500-1000', value: '500-1000' },
            { label: '1000+', value: '1000+' }
        ];
    }

    get noPartReasonOptions() {
        return [
            { label: 'No Fault Found', value: 'No Fault Found' },
            { label: 'Legacy Part', value: 'Legacy Part' },
            { label: 'Missing Part', value: 'Missing Part' }
        ];
    }

    /* ---------- out-of-scope: Case Information combobox options ---------- */
    get mainAreaOptions() {
        return [
            { label: 'Engine', value: 'engine' },
            { label: 'Transmission', value: 'transmission' },
            { label: 'Electrical', value: 'electrical' },
            { label: 'Hydraulics', value: 'hydraulics' }
        ];
    }

    get subAreaOptions() {
        return [
            { label: 'Sub Area 1', value: 'sub1' },
            { label: 'Sub Area 2', value: 'sub2' }
        ];
    }

    get priorityOptions() {
        return [
            { label: 'Low', value: 'low' },
            { label: 'Medium', value: 'medium' },
            { label: 'High', value: 'high' },
            { label: 'Critical', value: 'critical' }
        ];
    }

    get severityOptions() {
        return [
            { label: '1 - Critical', value: '1' },
            { label: '2 - High', value: '2' },
            { label: '3 - Medium', value: '3' },
            { label: '4 - Low', value: '4' }
        ];
    }

    /* ---------- Utilities ---------- */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body) {
            if (Array.isArray(err.body)) {
                return err.body.map((b) => b.message).join(', ');
            }
            if (err.body.message) return err.body.message;
        }
        return err.message || 'Unknown error';
    }
}