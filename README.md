# 🔨 Apex Trigger Forge

**Apex Trigger Forge** is a modular, metadata-driven trigger framework for Salesforce. It allows you to cleanly manage complex business logic, eliminate monolithic trigger files, and control execution dynamically — all without sacrificing bulk safety or performance.

---

## 🚀 Features

- 🧩 **Pluggable Logic Blocks**  
  Define modular units of trigger logic using custom metadata (`Trigger_Logic_Control__mdt`) so you can enable, disable, and reroute execution without touching code.

- 🔄 **Batch Reprocessing Support**  
  Includes a robust record reprocessing utility with live progress tracking and retry-safe batch Apex logic.

- ⚙️ **Dynamic Class Resolution**  
  Specify handler class names in metadata — or let the framework intelligently infer them from sObject names.

- 📓 **Optional Logging Framework**  
  Toggle detailed execution logs via custom settings at the org or user level. Supports both custom object logging and platform events.

- 🔐 **Trigger Context Control**  
  Prevent duplicate executions in complex recursion scenarios with automatic context tracking.

---

## 📦 Installation

You can deploy using your preferred method (Salesforce DX, Change Sets, etc.). The package includes:

- Apex classes (framework core, batch jobs, logging)
- Custom Metadata: `Trigger_Logic_Control__mdt`
- Custom Setting: `Trigger_Settings__c`
- Platform Event (optional): `Trigger_Log__e`
- Lightning Web Component (optional UI for batch reprocessing)

---

## 🛠️ How It Works

1. **Create a Trigger Handler Class**
   ```apex
   public class AccountTriggerHandler implements TriggerHandler {
       public override List<SObject> handleBeforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
           // your logic here
           return newList;
       }
       // implement other contexts as needed
   }
   ```

2. **Register the Logic via Metadata**
   Create a `Trigger_Logic_Control__mdt` record with:
   - `SObject_Type__c = 'Account'`
   - `Trigger_Context__c = 'before_update'`
   - `Logic_Name__c = 'yourLogicBlock'`
   - `Trigger_Handler_Class_Name__c = 'AccountTriggerHandler'`

3. **Trigger Remains Clean**
   Your trigger just delegates:
   ```apex
trigger AccountTrigger_Sample on Account  (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    AccountTriggerHandler_Sample handler = new AccountTriggerHandler_Sample();

    // Determine trigger context string
    String context = TriggerLogicController.getTriggerContext(
        Trigger.isBefore,
        Trigger.isAfter,
        Trigger.isInsert,
        Trigger.isUpdate,
        Trigger.isDelete,
        Trigger.isUndelete
    );

    // Dispatch if context is valid
    if (!String.isBlank(context)) {
        try{
            TriggerLogicController.dispatch(
                handler,
                context,
                Trigger.isDelete ? Trigger.old : Trigger.new,
                Trigger.oldMap
            );
        }catch(exception e){
            TriggerLogicController.log('FATAL ERROR in AccountTriggerHandler_Sample Trigger\n'+ 
                                        context+'\n'+ 
                                        e.getStackTraceString()+'\n'+
                                        e.getMessage()+'\n'+
                                        String.valueOf(e.getLineNumber()), TriggerLogicController.LogLevel.ERROR);
        }
        TriggerLogicController.flushLogs();
    }
}
   ```

---

## 🧪 Reprocessing Records

Included LWC utility lets you:
- Select logic blocks
- Preview records
- Run batch jobs
- View live execution logs

Ideal for retrying failed logic or post-migration processing.

---

## 🧬 Design Philosophy

> _“Your triggers should be smart, not cluttered. Forge the logic once—let the metadata decide when it runs.”_

This framework is built with **modularity**, **traceability**, and **respect for platform limits** in mind. It’s meant for teams that want precision control over logic execution in growing orgs.

---

## 📖 Docs & Examples

> Coming soon: full documentation and example metadata configs.

For now, explore the `examples/` folder or reach out via Issues or Discussions.

---

## 🙌 Credits

Developed by Kenji776
Inspired by battle-tested trigger patterns and forged for clarity, safety, and power.

---

## ⚠️ Disclaimer

This project is provided as-is. Always test thoroughly in a sandbox before using in production environments.
