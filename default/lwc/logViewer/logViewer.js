import { LightningElement, api } from 'lwc';
import isLoggingEnabled from '@salesforce/apex/LogViewerController.getIsLoggingEnabled';
import getLogs from '@salesforce/apex/LogViewerController.getLogs';

export default class LogViewer extends LightningElement {
    @api recordId;
    logs = [];
    selectedLog;
    isLoading = false;
    loggingEnabled;
    formattedLogHtml = '';
    filterText = '';

    columns = [
        { 
            label: 'Timestamp', 
            fieldName: 'CreatedDate', 
            type: 'date', 
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                hour12: true
            },
            sortable: true 
        },
        { label: 'Trigger', fieldName: 'Trigger_Name__c' },
        { label: 'Context', fieldName: 'Context__c' },
        {
            type: 'button',
            typeAttributes: {
                label: 'View',
                name: 'view_details',
                variant: 'brand'
            }
        }
    ];

    get isLoggingEnabled() {
        return this.loggingEnabled;
    }

    async connectedCallback() {
        this.loadLogs();
        this.loggingEnabled = await isLoggingEnabled();
    }

    loadLogs() {
        this.isLoading = true;
        getLogs({ recordId: this.recordId })
            .then(result => {
                this.logs = result;
                console.log('Logs loaded:', result);
            })
            .catch(error => {
                console.error('Error loading logs:', error);
                this.logs = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    prepareFormattedLogLines() {
        console.log('Preparing formatted log lines...');
        if (!this.selectedLog || !this.selectedLog.Message__c) {
            console.warn('No selected log or log message is empty.');
            this.formattedLogHtml = '';
            return;
        }

        let fullMessage = this.selectedLog.Message__c;

        if (this.recordId && fullMessage.includes(this.recordId)) {
            console.log(`Highlighting recordId: ${this.recordId}`);
            const safeRecordId = this.recordId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const regex = new RegExp(safeRecordId, 'g');
            fullMessage = fullMessage.replace(
                regex,
                `<span class="highlight-record-id">${this.recordId}</span>`
            );
        }

        const originalLines = fullMessage.split('\n');

        const htmlLines = originalLines.map((line, index) => {
            const shouldShow = !this.filterText || line.toLowerCase().includes(this.filterText.toLowerCase());
            if (!shouldShow) return ''; // skip rendering this line but preserve its index

            let cssClass = '';
            if (line.includes('[ERROR]')) cssClass = 'log-error';
            else if (line.includes('[WARNING]')) cssClass = 'log-warning';
            else if (line.includes('[SUCCESS]')) cssClass = 'log-success';
            else if (line.includes('[START]')) cssClass = 'log-start';
            else if (line.includes('[END]')) cssClass = 'log-end';

            const lineNumber = `<span class="log-line-number">${index + 1}</span>`;
            return `<div class="log-line ${cssClass}">${lineNumber} ${line}</div>`;
        }).filter(html => html !== ''); // remove empty lines skipped by filter

        this.formattedLogHtml = htmlLines.join('');
        console.log('Formatted log HTML set (filtered with static line numbers).');
    }



    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;

        if (action === 'view_details') {
            console.log('Selected log:', row);
            this.selectedLog = row;
            this.prepareFormattedLogLines();
        }
    }

    renderedCallback() {
        if (this.formattedLogHtml) {
            const logContainer = this.template.querySelector('.log-container');
            if (logContainer) {
                logContainer.innerHTML = this.formattedLogHtml;
                console.log('Log HTML injected into DOM.');
            }
        }
    }

    refreshLogs() {
        this.loadLogs();
    }

    closeModal() {
        console.log('Closing modal');
        this.selectedLog = null;
        this.formattedLogHtml = '';
    }

    handleFilterChange(event) {
        this.filterText = event.target.value;
        this.prepareFormattedLogLines();
    }

    downloadLog() {
        if (!this.selectedLog || !this.selectedLog.Message__c) return;

        const logText = this.selectedLog.Message__c;
        const fileName = `TriggerLog_${this.selectedLog.Id}.txt`;
        const encodedLog = encodeURIComponent(logText);
        const dataUri = `data:text/plain;charset=utf-8,${encodedLog}`;

        const downloadLink = document.createElement('a');
        downloadLink.href = dataUri;
        downloadLink.download = fileName;
        downloadLink.style.display = 'none';

        document.body.appendChild(downloadLink);
        downloadLink.click();
        document.body.removeChild(downloadLink);
    }

    downloadHTMLLog() {
        if (!this.selectedLog || !this.selectedLog.Message__c) return;

        const fileName = `TriggerLog_${this.selectedLog.Id}.html`;
        const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Trigger Log ${this.selectedLog.Id}</title>
    <style>
        body {
            font-family: monospace;
            background-color: #f8f8f8;
            padding: 20px;
        }
        .log-error { color: #c23934; font-weight: bold; }
        .log-warning { color: #e67300; font-weight: bold; }
        .log-success { color: #19c55b; font-weight: bold; }
        .log-start { color: #3a49d6; font-weight: bold; }
        .log-end { color: #4219b3; font-weight: bold; }
        .highlight-record-id { color: green; font-weight: bold; }
        .log-line { font-family: monospace; white-space: pre-wrap; padding-left: 4px;}
        .log-line-number {display: inline-block; width: 40px; text-align: right; margin-right: 8px; color: #888; user-select: none;}
    </style>
</head>
<body>
    <h1>Trigger Log Details</h1>
    <p><strong>Trigger:</strong> ${this.selectedLog.Trigger_Name__c}</p>
    <p><strong>Context:</strong> ${this.selectedLog.Context__c}</p>
    <p><strong>Timestamp:</strong> ${this.selectedLog.CreatedDate}</p>
    <p><strong>User:</strong> ${this.selectedLog.User__c}</p>
    <p><strong>SObject Type:</strong> ${this.selectedLog.SObject_Type__c}</p>
    <hr/>
    <pre>${this.formattedLogHtml}</pre>
</body>
</html>`;

        const encodedHtml = encodeURIComponent(htmlContent);
        const dataUri = `data:text/html;charset=utf-8,${encodedHtml}`;

        const downloadLink = document.createElement('a');
        downloadLink.href = dataUri;
        downloadLink.download = fileName;
        downloadLink.style.display = 'none';

        document.body.appendChild(downloadLink);
        downloadLink.click();
        document.body.removeChild(downloadLink);
    }
}
