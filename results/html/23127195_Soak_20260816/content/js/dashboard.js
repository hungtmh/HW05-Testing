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
    createTable($("#statisticsTable"), {"supportsControllersDiscrimination": true, "overall": {"data": ["Total", 153366, 0, 0.0, 5.70542362714028, 0, 121, 5.0, 14.0, 19.0, 36.0, 170.43961832620974, 760.6760950780346, 54.535483848057844], "isController": false}, "titles": ["Label", "#Samples", "FAIL", "Error %", "Average", "Min", "Max", "Median", "90th pct", "95th pct", "99th pct", "Transactions/s", "Received", "Sent"], "items": [{"data": ["02 GET /api/products?search", 21972, 0, 0.0, 4.608410704533062, 0, 97, 3.0, 10.0, 14.0, 25.0, 24.469231934285435, 11.973723749406979, 4.800660853432953], "isController": false}, {"data": ["04 POST /api/cart", 21867, 0, 0.0, 2.3497964970046024, 0, 76, 2.0, 4.0, 6.0, 14.0, 24.427489443463884, 7.013361226932014, 10.054069738418532], "isController": false}, {"data": ["TC-01 AUTH (auth-heavy)", 22014, 0, 0.0, 4.8005814481693605, 0, 86, 3.0, 10.0, 13.0, 23.0, 24.460869719812262, 15.37523091966881, 6.139104998038819], "isController": true}, {"data": ["TC-03 TRANSACTION (transactional)", 21865, 0, 0.0, 25.909627258175096, 2, 225, 22.0, 44.0, 55.0, 84.0, 24.421081318347476, 725.9678757442762, 39.30384155078334], "isController": true}, {"data": ["01 POST /api/login", 22014, 0, 0.0, 4.800490596892912, 0, 86, 3.0, 10.0, 13.0, 23.0, 24.465219246772644, 15.377964877298824, 6.140196627363838], "isController": false}, {"data": ["TC-02 BROWSE (read-heavy)", 21972, 0, 0.0, 9.23052066266153, 0, 102, 7.0, 18.0, 23.0, 37.0, 24.473919881662603, 23.00646332671324, 9.307226754816368], "isController": true}, {"data": ["05 POST /api/apply-coupon", 21867, 0, 0.0, 6.492248593771449, 0, 121, 4.0, 15.0, 19.0, 32.0, 24.427598595136597, 9.582578986213326, 10.127665362733138], "isController": false}, {"data": ["03 GET /api/products/{id}", 21916, 0, 0.0, 4.6336010220843376, 0, 97, 3.0, 10.0, 14.0, 25.0, 24.44252615894557, 11.044445331442372, 4.511364691446008], "isController": false}, {"data": ["06 POST /api/checkout", 21865, 0, 0.0, 10.258632517722319, 2, 89, 9.0, 17.0, 22.0, 36.9900000000016, 24.426128416753432, 7.525634465613507, 10.692782698363846], "isController": false}, {"data": ["07 GET /api/orders/my-orders", 21865, 0, 0.0, 6.8090555682597715, 0, 81, 6.0, 12.0, 16.0, 25.0, 24.426128416753432, 701.9973026195808, 8.43861853012016], "isController": false}]}, function(index, item){
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
    createTable($("#top5ErrorsBySamplerTable"), {"supportsControllersDiscrimination": false, "overall": {"data": ["Total", 153366, 0, "", "", "", "", "", "", "", "", "", ""], "isController": false}, "titles": ["Sample", "#Samples", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors"], "items": [{"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}]}, function(index, item){
        return item;
    }, [[0, 0]], 0);

});
