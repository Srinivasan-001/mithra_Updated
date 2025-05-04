# How to Add Hotspot Data to Firebase Firestore

This guide explains how to add hotspot data to your Firebase Firestore database so that the updated safety app can display them and calculate safer routes.

**Prerequisites:**

1.  **Firebase Project:** You need an active Firebase project linked to your Flutter application.
2.  **Firestore Database:** Your Firebase project must have Firestore Database enabled. If you haven't enabled it, go to your Firebase project console, select "Firestore Database" from the Build menu, and click "Create database". Choose "Start in production mode" or "Start in test mode" (for development, test mode is easier initially, but remember to secure your rules before launch). Select a location for your database.
3.  **Firebase Configuration in Flutter:** Your Flutter app must be correctly configured to connect to your Firebase project (e.g., `google-services.json` for Android, `GoogleService-Info.plist` for iOS, and Firebase initialization in your `main.dart`). The provided code assumes this setup is already done.

**Steps to Add Hotspot Data:**

1.  **Navigate to Firestore:** Open your Firebase project console and go to the "Firestore Database" section.

2.  **Create the `hotspots` Collection:**
    *   If you don't already have a collection named `hotspots`, click on "+ Start collection".
    *   Enter `hotspots` as the Collection ID.
    *   Click "Next".

3.  **Add a Hotspot Document:**
    *   Firestore will prompt you to add your first document. Click "Auto-ID" to let Firestore generate a unique ID for this hotspot.
    *   Now, you need to add fields to this document. The app code expects specific field names and types:
        *   **Field 1:**
            *   **Field name:** `name`
            *   **Type:** `string`
            *   **Value:** Enter a descriptive name for the hotspot (e.g., "High Crime Corner", "Poorly Lit Street Section").
        *   **Field 2:**
            *   **Field name:** `location`
            *   **Type:** `geopoint`
            *   **Value:** Enter the latitude and longitude for the center of the hotspot. Firestore provides fields for Latitude and Longitude.
                *   *Latitude:* Enter the latitude value (e.g., `40.7128`).
                *   *Longitude:* Enter the longitude value (e.g., `-74.0060`).
        *   **Field 3:**
            *   **Field name:** `radius`
            *   **Type:** `number`
            *   **Value:** Enter the radius of the hotspot zone **in meters** (e.g., `100` for a 100-meter radius). Make sure this is a numerical value (integer or double).
    *   You can add more optional fields if needed for your own reference, but `name`, `location` (as a geopoint), and `radius` (as a number) are essential for the app's functionality.

4.  **Save the Document:** Click "Save". You have now added your first hotspot.

5.  **Add More Hotspots:**
    *   To add more hotspots, select the `hotspots` collection in the left-hand panel.
    *   Click "+ Add document".
    *   Click "Auto-ID" again.
    *   Repeat step 3 to add the `name` (string), `location` (geopoint), and `radius` (number) fields with the appropriate values for the new hotspot.
    *   Click "Save".

**Data Structure Summary:**

Your `hotspots` collection in Firestore should look like this:

```
/hotspots (collection)
    /document_id_1 (document)
        name: "Example Hotspot 1" (string)
        location: GeoPoint(latitude, longitude) (geopoint)
        radius: 150 (number)
    /document_id_2 (document)
        name: "Another Danger Zone" (string)
        location: GeoPoint(latitude, longitude) (geopoint)
        radius: 75 (number)
    ... (more documents)
```

**Important Considerations:**

*   **Data Types:** Ensure you use the correct data types: `string` for `name`, `geopoint` for `location`, and `number` for `radius`.
*   **Field Names:** Use the exact field names (`name`, `location`, `radius`) as the app code expects them.
*   **Units:** The `radius` must be in **meters**.
*   **Real-time Updates:** The app uses a stream (`getHotspotsStream`) to listen for changes in the `hotspots` collection. Any hotspots you add, update, or delete in Firestore will automatically reflect in the app shortly after (usually within seconds), without needing an app restart.
*   **API Key:** Remember to replace `"YOUR_GOOGLE_API_KEY"` in `/home/ubuntu/safety_app_update/lib/features/map/presentation/screens/map_screen.dart` with your actual Google Maps API key, ensuring it has the Directions API enabled.
*   **Security Rules:** For production apps, configure Firestore security rules to control who can read and write hotspot data. Initially, you might allow authenticated users to read, but restrict write access to administrators.

By following these steps, you can effectively manage the hotspot areas used by your women's safety application.
