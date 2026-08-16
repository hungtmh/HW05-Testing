/*
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
var showControllersOnly = false;
var seriesFilter = "";
var filtersOnlySampleSeries = true;

/*
 * Add header in statistics table to group metrics by category
 * format
 *
 */
function summaryTableHeader(header) {
    var newRow = header.insertRow(-1);
    newRow.className = "tablesorter-no-sort";
    var cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 1;
    cell.innerHTML = "Requests";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 3;
    cell.innerHTML = "Executions";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 7;
    cell.innerHTML = "Response Times (ms)";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 1;
    cell.innerHTML = "Throughput";
    newRow.appendChild(cell);

    cell = document.createElement('th');
    cell.setAttribute("data-sorter", false);
    cell.colSpan = 2;
    cell.innerHTML = "Network (KB/sec)";
    newRow.appendChild(cell);
}

/*
 * Populates the table identified by id parameter with the specified data and
 * format
 *
 */
function createTable(table, info, formatter, defaultSorts, seriesIndex, headerCreator) {
    var tableRef = table[0];

    // Create header and populate it with data.titles array
    var header = tableRef.createTHead();

    // Call callback is available
    if(headerCreator) {
        headerCreator(header);
    }

    var newRow = header.insertRow(-1);
    for (var index = 0; index < info.titles.length; index++) {
        var cell = document.createElement('th');
        cell.innerHTML = info.titles[index];
        newRow.appendChild(cell);
    }

    var tBody;

    // Create overall body if defined
    if(info.overall){
        tBody = document.createElement('tbody');
        tBody.className = "tablesorter-no-sort";
        tableRef.appendChild(tBody);
        var newRow = tBody.insertRow(-1);
        var data = info.overall.data;
        for(var index=0;index < data.length; index++){
            var cell = newRow.insertCell(-1);
            cell.innerHTML = formatter ? formatter(index, data[index]): data[index];
        }
    }

    // Create regular body
    tBody = document.createElement('tbody');
    tableRef.appendChild(tBody);

    var regexp;
    if(seriesFilter) {
        regexp = new RegExp(seriesFilter, 'i');
    }
    // Populate body with data.items array
    for(var index=0; index < info.items.length; index++){
        var item = info.items[index];
        if((!regexp || filtersOnlySampleSeries && !info.supportsControllersDiscrimination || regexp.test(item.data[seriesIndex]))
                &&
                (!showControllersOnly || !info.supportsControllersDiscrimination || item.isController)){
            if(item.data.length > 0) {
                var newRow = tBody.insertRow(-1);
                for(var col=0; col < item.data.length; col++){
                    var cell = newRow.insertCell(-1);
                    cell.innerHTML = formatter ? formatter(col, item.data[col]) : item.data[col];
                }
            }
        }
    }

    // Add support of columns sort
    table.tablesorter({sortList : defaultSorts});
}

$(document).ready(function() {

    // Customize table sorter default options
    $.extend( $.tablesorter.defaults, {
        theme: 'blue',
        cssInfoBlock: "tablesorter-no-sort",
        widthFixed: true,
        widgets: ['zebra']
    });

    var data = {"OkPercent": 100.0, "KoPercent": 0.0};
    var dataset = [
        {
            "label" : "FAIL",
            "data" : data.KoPercent,
            "color" : "#FF6347"
        },
        {
            "label" : "PASS",
            "data" : data.OkPercent,
            "color" : "#9ACD32"
        }];
    $.plot($("#flot-requests-summary"), dataset, {
        series : {
            pie : {
                show : true,
                radius : 1,
                label : {
                    show : true,
                    radius : 3 / 4,
                    formatter : function(label, series) {
                        return '<div style="font-size:8pt;text-align:center;padding:2px;color:white;">'
                            + label
                            + '<br/>'
                            + Math.round10(series.percent, -2)
                            + '%</div>';
                    },
                    background : {
                        opacity : 0.5,
                        color : '#000'
                    }
                }
            }
        },
        legend : {
            show : true
        }
    });

    // Creates APDEX table
    createTable($("#apdexTable"), {"supportsControllersDiscrimination": true, "overall": {"data": [1.0, 500, 1500, "Total"], "isController": false}, "titles": ["Apdex", "T (Toleration threshold)", "F (Frustration threshold)", "Label"], "items": [{"data": [1.0, 500, 1500, "02 GET /api/products?search"], "isController": false}, {"data": [1.0, 500, 1500, "04 POST /api/cart"], "isController": false}, {"data": [1.0, 500, 1500, "TC-01 AUTH (auth-heavy)"], "isController": true}, {"data": [1.0, 500, 1500, "TC-03 TRANSACTION (transactional)"], "isController": true}, {"data": [1.0, 500, 1500, "01 POST /api/login"], "isController": false}, {"data": [1.0, 500, 1500, "TC-02 BROWSE (read-heavy)"], "isController": true}, {"data": [1.0, 500, 1500, "05 POST /api/apply-coupon"], "isController": false}, {"data": [1.0, 500, 1500, "03 GET /api/products/{id}"], "isController": false}, {"data": [1.0, 500, 1500, "06 POST /api/checkout"], "isController": false}, {"data": [1.0, 500, 1500, "07 GET /api/orders/my-orders"], "isController": false}]}, function(index, item){
        switch(index){
            case 0:
                item = item.toFixed(3);
                break;
            case 1:
            case 2:
                item = formatDuration(item);
                break;
        }
        return item;
    }, [[0, 0]], 3);

    // Create statistics table
    createTable($("#statisticsTable"), {"supportsControllersDiscrimination": true, "overall": {"data": ["Total", 18749, 0, 0.0, 3.7483599125286835, 0, 55, 3.0, 8.0, 9.0, 15.0, 62.52688799586467, 56.49350636661886, 19.984633197712228], "isController": false}, "titles": ["Label", "#Samples", "FAIL", "Error %", "Average", "Min", "Max", "Median", "90th pct", "95th pct", "99th pct", "Transactions/s", "Received", "Sent"], "items": [{"data": ["02 GET /api/products?search", 2695, 0, 0.0, 3.096474953617815, 0, 35, 3.0, 5.0, 7.0, 11.039999999999964, 9.050822298270774, 4.428277349561564, 1.7757214315579841], "isController": false}, {"data": ["04 POST /api/cart", 2663, 0, 0.0, 2.320690950056327, 0, 30, 2.0, 4.0, 4.0, 6.0, 9.086380324557451, 2.608784975995987, 3.7398342548093324], "isController": false}, {"data": ["TC-01 AUTH (auth-heavy)", 2723, 0, 0.0, 2.8740359897172176, 0, 33, 2.0, 5.0, 7.0, 10.0, 9.08048046846342, 5.70762506711152, 2.278987773823339], "isController": true}, {"data": ["TC-03 TRANSACTION (transactional)", 2663, 0, 0.0, 17.27487795719111, 4, 67, 16.0, 25.0, 29.0, 43.0, 9.060165212776091, 43.20566750992604, 14.581575509315334], "isController": true}, {"data": ["01 POST /api/login", 2723, 0, 0.0, 2.8740359897172176, 0, 33, 2.0, 5.0, 7.0, 10.0, 9.082903593801078, 5.709148146310467, 2.2795959214910906], "isController": false}, {"data": ["TC-02 BROWSE (read-heavy)", 2695, 0, 0.0, 6.103525046382182, 0, 38, 5.0, 9.0, 11.0, 17.0, 9.04371520518663, 8.487029651305214, 3.4336184854629406], "isController": true}, {"data": ["05 POST /api/apply-coupon", 2663, 0, 0.0, 3.6503942921517045, 0, 27, 3.0, 6.0, 8.0, 13.0, 9.086566349336337, 3.5645314312706864, 3.7672547034411576], "isController": false}, {"data": ["03 GET /api/products/{id}", 2679, 0, 0.0, 3.0250093318402427, 0, 30, 3.0, 5.0, 7.0, 11.0, 9.073543457497612, 4.099968930353187, 1.6747067514326646], "isController": false}, {"data": ["06 POST /api/checkout", 2663, 0, 0.0, 8.414945550131446, 2, 55, 8.0, 12.0, 15.0, 27.0, 9.087310524627533, 2.7917238782477836, 3.97806439731305], "isController": false}, {"data": ["07 GET /api/orders/my-orders", 2663, 0, 0.0, 2.888847164851674, 0, 32, 3.0, 4.0, 6.0, 10.0, 9.087465576489297, 34.370103874116595, 3.139472430905573], "isController": false}]}, function(index, item){
        switch(index){
            // Errors pct
            case 3:
                item = item.toFixed(2) + '%';
                break;
            // Mean
            case 4:
            // Mean
            case 7:
            // Median
            case 8:
            // Percentile 1
            case 9:
            // Percentile 2
            case 10:
            // Percentile 3
            case 11:
            // Throughput
            case 12:
            // Kbytes/s
            case 13:
            // Sent Kbytes/s
                item = item.toFixed(2);
                break;
        }
        return item;
    }, [[0, 0]], 0, summaryTableHeader);

    // Create error table
    createTable($("#errorsTable"), {"supportsControllersDiscrimination": false, "titles": ["Type of error", "Number of errors", "% in errors", "% in all samples"], "items": []}, function(index, item){
        switch(index){
            case 2:
            case 3:
                item = item.toFixed(2) + '%';
                break;
        }
        return item;
    }, [[1, 1]]);

        // Create top5 errors by sampler
    createTable($("#top5ErrorsBySamplerTable"), {"supportsControllersDiscrimination": false, "overall": {"data": ["Total", 18749, 0, "", "", "", "", "", "", "", "", "", ""], "isController": false}, "titles": ["Sample", "#Samples", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors"], "items": [{"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}]}, function(index, item){
        return item;
    }, [[0, 0]], 0);

});
