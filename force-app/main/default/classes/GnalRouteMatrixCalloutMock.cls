@IsTest
public class GnalRouteMatrixCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();

        // GnalTravelTimeServiceWithGeocoding uses POST for the route matrix call.
        if (req != null && req.getMethod() == 'POST') {
            res.setStatusCode(200);
            // Two destinations: first is faster/shorter.
            res.setBody(
                '[' +
                    '{"originIndex":0,"destinationIndex":0,"status":"OK","duration":"100s","distanceMeters":5000},' +
                    '{"originIndex":0,"destinationIndex":1,"status":"OK","duration":"200s","distanceMeters":7000}' +
                ']'
            );
            return res;
        }

        res.setStatusCode(400);
        res.setBody('Unsupported request');
        return res;
    }
}

