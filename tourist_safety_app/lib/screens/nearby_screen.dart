import 'package:flutter/material.dart';

class NearbyScreen extends StatefulWidget {
  final String type; // "police" or "hospital"

  const NearbyScreen({super.key, required this.type});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  // ===== Sri Lanka real places data =====
  final List<Map<String, dynamic>> policeStations = [
    {
      "name": "Colombo Fort Police Station",
      "address": "Colombo Fort, Colombo 01",
      "phone": "011-2-433333",
      "distance": "0.5 km",
      "open": true,
    },
    {
      "name": "Kollupitiya Police Station",
      "address": "Galle Road, Colombo 03",
      "phone": "011-2-574433",
      "distance": "1.2 km",
      "open": true,
    },
    {
      "name": "Bambalapitiya Police Station",
      "address": "Bambalapitiya, Colombo 04",
      "phone": "011-2-588888",
      "distance": "2.1 km",
      "open": true,
    },
    {
      "name": "Wellawatte Police Station",
      "address": "Wellawatte, Colombo 06",
      "phone": "011-2-552222",
      "distance": "3.4 km",
      "open": true,
    },
    {
      "name": "Nugegoda Police Station",
      "address": "High Level Road, Nugegoda",
      "phone": "011-2-852222",
      "distance": "5.8 km",
      "open": true,
    },
  ];

  final List<Map<String, dynamic>> hospitals = [
    {
      "name": "National Hospital of Sri Lanka",
      "address": "Regent Street, Colombo 10",
      "phone": "011-2-691111",
      "distance": "1.0 km",
      "open": true,
    },
    {
      "name": "Colombo National Hospital",
      "address": "Colombo 08",
      "phone": "011-2-695411",
      "distance": "1.3 km",
      "open": true,
    },
    {
      "name": "Lanka Hospitals",
      "address": "578 Elvitigala Mw, Colombo 05",
      "phone": "011-5-430000",
      "distance": "2.5 km",
      "open": true,
    },
    {
      "name": "Asiri Hospital",
      "address": "181 Kirula Road, Colombo 05",
      "phone": "011-4-520000",
      "distance": "2.9 km",
      "open": true,
    },
    {
      "name": "Nawaloka Hospital",
      "address": "23 Deshamanya H.K. Dharmadasa Mw",
      "phone": "011-2-544444",
      "distance": "3.2 km",
      "open": true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isPolice = widget.type == "police";
    final Color themeColor = isPolice ? Colors.indigo : Colors.green;
    final IconData themeIcon =
        isPolice ? Icons.local_police : Icons.local_hospital;
    final String title =
        isPolice ? "Nearby Police Stations" : "Nearby Hospitals";
    final List<Map<String, dynamic>> placesList =
        isPolice ? policeStations : hospitals;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: Column(
        children: [
          // ===== TOP BANNER =====
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: themeColor.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.location_on, color: themeColor),
                const SizedBox(width: 8),
                Text(
                  "Showing nearest ${placesList.length} locations",
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // ===== LIST =====
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: placesList.length,
              itemBuilder: (context, index) {
                final place = placesList[index];
                return _buildPlaceCard(place, themeColor, themeIcon, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(
    Map<String, dynamic> place,
    Color themeColor,
    IconData themeIcon,
    int index,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== NAME + DISTANCE =====
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(themeIcon, color: themeColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place["name"],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        place["address"],
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // ===== DISTANCE BADGE =====
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    place["distance"],
                    style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ===== PHONE + OPEN STATUS + BUTTONS =====
            Row(
              children: [
                // Open/Closed badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: place["open"]
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: place["open"] ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        place["open"] ? "Open 24/7" : "Closed",
                        style: TextStyle(
                          color: place["open"] ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Call button
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Calling ${place["phone"]}..."),
                        backgroundColor: themeColor,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.phone, color: Colors.white, size: 16),
                  label: const Text(
                    "Call",
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),

                const SizedBox(width: 8),

                // Navigate button
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Opening directions to ${place["name"]}..."),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.directions, color: Colors.white, size: 16),
                  label: const Text(
                    "Go",
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}