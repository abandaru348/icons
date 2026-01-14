({
    doInit: function (component) {
        try {
            var pr = component.get('v.pageReference');
            var state = pr && pr.state ? pr.state : {};
            // When clicking "New" from the Case related list, Case__c is usually passed via defaultFieldValues.
            // We don't decode defaultFieldValues here (the nested LWC handles that), but for "New" overrides the
            // backgroundContext is often the only place we can find the parent Case record.
            //
            // IMPORTANT: This regex is NOT the URL we navigate to. It's the *background page* URL that Salesforce
            // includes in page state so the override can understand "where the user came from".
            // Example backgroundContext values:
            // - "1%2Flightning%2Fr%2FCase%2F500XXXXXXXXXXXXXXX%2Fview" (URL-encoded)
            // - "/lightning/r/Case/500XXXXXXXXXXXXXXX/view"
            // - "/Case/500XXXXXXXXXXXXXXX" (legacy / simplified forms)
            var background = state.backgroundContext;
            if (background && typeof background === 'string') {
                // backgroundContext is frequently URL-encoded; decode when possible.
                try {
                    background = decodeURIComponent(background);
                } catch (e1) {
                    // ignore decode failures
                }

                // Extract the Case Id from common Lightning URL shapes.
                // Prefer the fully-qualified Lightning record URL, then fall back to simpler forms.
                var match =
                    background.match(/\/lightning\/r\/Case\/([a-zA-Z0-9]{15,18})(?:[/?#]|$)/) ||
                    background.match(/\/Case\/([a-zA-Z0-9]{15,18})(?:[/?#]|$)/);

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

