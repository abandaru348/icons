({
    doInit: function (component) {
        try {
            var pr = component.get('v.pageReference');
            var state = pr && pr.state ? pr.state : {};
            // When clicking "New" from the Case related list, Case__c is usually passed via defaultFieldValues.
            // We don't decode here (LWC also decodes), but we can also grab backgroundContext which often contains the Case Id.
            var background = state.backgroundContext;
            if (background && typeof background === 'string') {
                var match = background.match(/\/Case\/([a-zA-Z0-9]{15,18})/);
                if (match && match[1]) {
                    component.set('v.caseId', match[1]);
                    return;
                }
            }
        } catch (e) {
            // ignore
        }
    }
})

