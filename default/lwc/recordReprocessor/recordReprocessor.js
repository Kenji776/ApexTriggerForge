import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getEnabledLogicOptions from '@salesforce/apex/RecordReprocessorController.getEnabledLogicOptions';
import launchProcessingJob from '@salesforce/apex/RecordReprocessorController.launchProcessingJob';
import getAvailableSObjectTypes from '@salesforce/apex/RecordReprocessorController.getAvailableSObjectTypes';
import runPreviewQuery from '@salesforce/apex/RecordReprocessorController.runPreviewQuery';
import getNumRecords from '@salesforce/apex/RecordReprocessorController.getNumRecords';
import checkApexJobStatus from '@salesforce/apex/RecordReprocessorController.checkApexJobStatus';
import getDescribeFields from '@salesforce/apex/RecordReprocessorController.getDescribeFields';
import { subscribe, unsubscribe, onError, setDebugFlag, isEmpEnabled } from 'lightning/empApi';

import { createRecord } from 'lightning/uiRecordApi';

export default class TriggerLogicProcessor extends LightningElement {
    @track sObjectTypeOptions = [];
    @track sObjectType = 'Account';
    @track triggerContext = 'before_insert';
    @track logicData = [];
    @track whereClause = '';
    @track recordPreview = [];
    @track recordIdsToProcess = [];
    @track queryRecordsSize = 0;
    @track showProgressModal = false;
    @track jobProgress = 0;
    @track jobStatusLabel = 'Starting...';
    @track page = 1;
    @track pageSize = 10;
    @track pagedRecords = []; // What gets shown
    @track totalPages = 1;
    @track showFieldModal = false;
    @track fieldOptions = [];
    @track selectedFields = ['id', 'name', 'createddate'];
    @track fieldTextAreaValue = 'id, name, createddate';
    @track batchSize = 100;
    @track batchesProcessed = 0;
    @track totalBatches = 0;
    @track errorCount = 0;
    @track batchJobExtendedStatus = '';
    @track selectedLogicMetadataIds = [];

    channelName = '/event/Trigger_Log__e';
    subscription = {};
    jobId = null;
    jobIntervalId = null;

    columns = [
        { label: 'Logic Name', fieldName: 'Logic_Name__c' },
        { label: 'Description', fieldName: 'Description__c', wrapText:true, initialWidth: 500 },
        { label: 'Trigger Context', fieldName: 'Trigger_Context__c' },
        { label: 'Enabled', fieldName: 'Is_Enabled__c' },
        { label: 'Known Required Fields', fieldName: 'Required_Input_Fields__c', wrapText:true, },
        { label: 'Apex Class', fieldName: 'Trigger_Handler_Class_Name__c', wrapText:true, }
    ];

    recordColumns = [
        { label: 'Record Id', fieldName: 'Id' },
        { label: 'Name', fieldName: 'Name' },
        { label: 'CreatedDate', fieldName: 'CreatedDate' }
    ];


    get triggerContextOptions() {
        return [
            { label: 'Before Insert', value: 'before_insert' },
            { label: 'Before Update', value: 'before_update' },
            { label: 'After Insert', value: 'after_insert' },
            { label: 'After Update', value: 'after_update' },
            { label: 'Before Delete', value: 'before_delete' },
            { label: 'After Delete', value: 'after_delete' },
            { label: 'After Undelete', value: 'after_undelete' }
        ];
    }

    @track executionLogs = [];
    @track liveLogColumns = [
        { label: 'Timestamp', fieldName: 'Timestamp__c' },
        { label: 'Message', fieldName: 'Message__c', wrapText: true },
        { label: 'Context', fieldName: 'Context__c' },
        { label: 'Trigger Name', fieldName: 'Trigger_Name__c' },
        { label: 'SObject Type', fieldName: 'SObject_Type__c' }
    ];





    get numRecords(){
        return this.queryRecordsSize;
    }
    get numPreviewecords(){
        return this.recordPreview.length;
    }
    get isJobRunning() {
        return this.jobStatusLabel !== 'Completed' && this.jobStatusLabel !== 'Failed';
    }
    async connectedCallback() {
        setDebugFlag(true);

        this.registerErrorListener();

        this.handleSubscribe();

        try {
            this.sObjectTypeOptions = await getAvailableSObjectTypes();
        } catch (error) {
            this.showToast('Error', 'Failed to load sObject types: ' + (error.body?.message || error.message));
        }

        try {
            this.queryRecordsSize = await getNumRecords({ sObjectType: this.sObjectType, whereClause: this.whereClause });
        } catch (error) {
            this.showToast('Error', 'Failed to get record count: ' + (error.body?.message || error.message));
        }
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }
    
    get isPreviousDisabled() {
        return this.page <= 1;
    }

    get isNextDisabled() {
        return this.page >= this.totalPages;
    }

    async handleSObjectTypeChange(e) {
        this.sObjectType = e.detail.value;

        try {
            this.fetchLogicOptions();
            this.queryRecordsSize = await getNumRecords({ sObjectType: this.sObjectType, whereClause: this.whereClause });
        } catch (error) {
            this.showToast('Error', 'Failed to change sObject type: ' + (error.body?.message || error.message));
        }
    }
    handleTriggerContextChange(e) {
        this.triggerContext = e.detail.value;
        this.fetchLogicOptions();
    }

    fetchLogicOptions() {
        if (this.sObjectType && this.triggerContext) {
            getEnabledLogicOptions({ sObjectType: this.sObjectType, triggerContext: this.triggerContext })
                .then(data => {
                    this.logicData = this.logicData = data; 
                    this.selectedLogicMetadataIds = [];
                })
                .catch(err => {
                    this.showToast('Error', 'Failed to fetch logic options: ' + (err.body?.message || err.message));
                });
        }
    }

    
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;

        console.log('Selected rows');
        console.log(JSON.stringify(selectedRows));
        this.selectedLogicMetadataIds = selectedRows.map(row => row.Id); // This will now be the true record Id

        console.log('Metadata logic ids');
        console.log(JSON.stringify(this.selectedLogicMetadataIds));

        // Initialize a Set using existing fields, all lowercased
        const existingFieldsSet = new Set(
            (this.selectedFields || []).map(f => f.trim().toLowerCase())
        );

        // Add new required input fields from selected rows
        selectedRows.forEach(row => {
            if (row.Required_Input_Fields__c) {
                row.Required_Input_Fields__c
                    .split(',')
                    .map(f => f.trim().toLowerCase())
                    .forEach(field => existingFieldsSet.add(field));
            }
        });

        // Update selectedFields with deduplicated and normalized values
        this.selectedFields = Array.from(existingFieldsSet);

        console.log('Selected fields is now');
        console.log(JSON.stringify(this.selectedFields, null, 2));
    }

    handleWhereClauseChange(e) {
        this.whereClause = e.detail.value;
    }

    async handlePreviewRecords() {
        if (!this.sObjectType) return;

        try {
            const result = await runPreviewQuery({ sObjectType: this.sObjectType, whereClause: this.whereClause });
            this.recordPreview = result;
            this.recordIdsToProcess = result.map(rec => rec.Id);
            this.page = 1;

            this.queryRecordsSize = await getNumRecords({ sObjectType: this.sObjectType, whereClause: this.whereClause });
            this.updatePagedRecords();
        } catch (err) {
            this.showToast('Error', 'Failed to preview records: ' + (err.body?.message || err.message));
        }
    }

    async fetchDescribeFields() {
        if (!this.sObjectType) return;

        try {
            const result = await getDescribeFields({ sObjectType: this.sObjectType });
            this.fieldOptions = result.map(field => ({ label: field, value: field }));
        } catch (e) {
            this.showToast('Error', 'Failed to fetch describe fields: ' + (e.body?.message || e.message));
        }
    }
    handleFieldSelection(event) {
        this.selectedFields = event.detail.value;
    }

    async handleRunLogic() {
        console.log('Calling handleRunLogic');

        if (this.selectedLogicMetadataIds.length === 0 || this.recordIdsToProcess.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Selections',
                    message: 'You must select at least one logic block and preview records first.',
                    variant: 'warning'
                })
            );
            return;
        }

        try {
            const confirmed = await LightningConfirm.open({
                message: `Are you sure you want to process ${this.queryRecordsSize} record(s) using ${this.selectedLogicMetadataIds.length} logic block(s): ${this.selectedLogicMetadataIds.join(', ')}?`,
                variant: 'header', // "default", "header", "confirmation"
                label: 'Confirm Record Processing'
            });

            if (!confirmed) {
                console.log('User canceled processing.');
                return;
            }

            // Proceed if user confirmed
            console.log('Launching job with logic:', this.selectedLogicMetadataIds);
            console.log(JSON.stringify(this.selectedLogicMetadataIds));
            const jobId = await launchProcessingJob({
                sObjectType: this.sObjectType,
                triggerContext: this.triggerContext,
                logicMetadataIds: this.selectedLogicMetadataIds,
                whereClause: this.whereClause,
                fields: [...new Set(this.selectedFields)],
                batchSize: this.batchSize
            });

            this.jobId = jobId;
            this.showProgressModal = true;
            this.jobProgress = 0;
            this.jobStatusLabel = 'Queued...';

            this.startPollingJobStatus();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Processing job launched successfully.',
                    variant: 'success'
                })
            );
        } catch (err) {
            console.error(err);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to launch processing job: ' + (err.body?.message || err.message),
                    variant: 'error'
                })
            );
        }
    }

    startPollingJobStatus() {
        this.jobIntervalId = setInterval(async () => {
            try {
                const result = await checkApexJobStatus({ jobId: this.jobId });

                console.log('Got job status info');
                console.log(JSON.stringify(result,null,2));

                this.jobStatusLabel = result.Status;
                this.jobProgress = result.PercentComplete;
                this.batchesProcessed = result.JobItemsProcessed;
                this.totalBatches = result.TotalJobItems;
                this.errorCount = result.NumberOfErrors;
                this.batchJobExtendedStatus = result.ExtendedStatus;

                if (['Completed', 'Failed', 'Aborted'].includes(result.Status)) {
                    clearInterval(this.jobIntervalId);
                    this.jobIntervalId = null;

                    // If it failed, show toast and possibly abort
                    if (['Failed', 'Aborted'].includes(result.Status)) {
                        this.showToast(
                            'Batch Job Failed',
                            `Error: ${this.batchJobExtendedStatus} 
                            The job failed after processing ${result.JobItemsProcessed} of ${result.TotalJobItems} batches. ${result.NumberOfErrors} 
                            errors were recorded.`,
                            'error'
                        );
                    }else{
                        this.showToast(
                            'Batch Job Completed',
                            `Job completed. Processed ${result.JobItemsProcessed} of ${result.TotalJobItems} batches. ${result.NumberOfErrors} errors were recorded.`,
                            'success'
                        );                        
                    }
                    
                    this.closeModal();
                }
            } catch (error) {
                clearInterval(this.jobIntervalId);
                this.jobIntervalId = null;
                this.showToast('Error', 'Failed to fetch job status: ' + (error.body?.message || error.message), 'error');
            }
        }, 1000);
    }

    updatePagedRecords() {
        const start = (this.page - 1) * this.pageSize;
        const end = this.page * this.pageSize;
        this.totalPages = Math.ceil(this.recordPreview.length / this.pageSize);
        this.pagedRecords = this.recordPreview.slice(start, end);
    }

    handleNextPage() {
        if (this.page < this.totalPages) {
            this.page++;
            this.updatePagedRecords();
        }
    }

    handlePrevPage() {
        if (this.page > 1) {
            this.page--;
            this.updatePagedRecords();
        }
    }
    closeModal(){
        this.showProgressModal = false;
    }
    
    openFieldModal() {
        this.showFieldModal = true;
        this.fetchDescribeFields();
    }

    closeFieldModal() {
        this.showFieldModal = false;
    }

    handleFieldSelection(event) {
        this.selectedFields = event.detail.value;
        this.fieldTextAreaValue = this.selectedFields.join(', ');
    }

    handleFieldTextAreaChange(event) {
        this.fieldTextAreaValue = event.detail.value;
    }

    handleBatchSizeChange(event){
        this.batchSize = event.detail.value;
    }
    applyFieldSelection() {
        this.selectedFields = this.fieldTextAreaValue.split(',').map(f => f.trim()).filter(f => f.length);
        this.showFieldModal = false;
    }

    // Handles subscribe button click
    handleSubscribe() {
        const messageCallback = (response) => {
            console.log('New message received: ', JSON.stringify(response));
            const payload = response.data?.payload;

            if (!payload) {
                console.warn('No payload in platform event response');
                return;
            }

            // Split and trim Related_Record_Ids__c
            const relatedIds = payload.Related_Record_Ids__c
                ? payload.Related_Record_Ids__c.split(',').map(id => id.trim())
                : [];

            // Match against recordIdsToProcess
            const matches = relatedIds.some(id => this.recordIdsToProcess.includes(id));

            if (!matches) {
                console.log('No matching related record IDs. Event skipped.');
                //return;
            }

            // Add to the top of executionLogs (limit to 50 entries)
            const newLog = {
                Id: response.data.event.replayId, // good enough for display key
                Timestamp__c: payload.Timestamp__c,
                Message__c: payload.Message__c,
                Context__c: payload.Context__c,
                Trigger_Name__c: payload.Trigger_Name__c,
                SObject_Type__c: payload.SObject_Type__c
            };

            this.executionLogs = [newLog, ...this.executionLogs].slice(0, 50);
        };

        subscribe(this.channelName, -1, messageCallback)
            .then((response) => {
                console.log('Subscribed to channel:', response.channel);
                this.subscription = response;
            })
            .catch((error) => {
                console.error('Failed to subscribe to platform event:', error);
                this.showToast('Error', 'Failed to subscribe to live logs: ' + (error.body?.message || error.message));
            });
    }


    handleUnsubscribe() {
        if (this.subscription && this.subscription.id) {
            // Invoke unsubscribe method of empApi
            unsubscribe(this.subscription, (response) => {
                console.log('unsubscribe() response: ', JSON.stringify(response));
                // Response is true for successful unsubscribe
            });
        }
    }

    registerErrorListener() {
        // Invoke onError empApi method
        onError((error) => {
            console.log('Received error from server: ', JSON.stringify(error));
            this.showToast('Error', JSON.stringify(error))
            // Error contains the server-side error
        });
    }

    showToast(title, message, variant = 'error') {
        console.error(message);
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
