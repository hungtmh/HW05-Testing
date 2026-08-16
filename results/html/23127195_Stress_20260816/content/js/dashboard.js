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
    createTable($("#apdexTable"), {"supportsControllersDiscrimination": true, "overall": {"data": [0.9621923491932998, 500, 1500, "Total"], "isController": false}, "titles": ["Apdex", "T (Toleration threshold)", "F (Frustration threshold)", "Label"], "items": [{"data": [0.9909878351697344, 500, 1500, "02 GET /api/products?search"], "isController": false}, {"data": [1.0, 500, 1500, "04 POST /api/cart"], "isController": false}, {"data": [0.9841949499401801, 500, 1500, "TC-01 AUTH (auth-heavy)"], "isController": true}, {"data": [0.8049438056259338, 500, 1500, "TC-03 TRANSACTION (transactional)"], "isController": true}, {"data": [0.9841949499401801, 500, 1500, "01 POST /api/login"], "isController": false}, {"data": [0.946945542660375, 500, 1500, "TC-02 BROWSE (read-heavy)"], "isController": true}, {"data": [0.9455076224456698, 500, 1500, "05 POST /api/apply-coupon"], "isController": false}, {"data": [0.9916285659089445, 500, 1500, "03 GET /api/products/{id}"], "isController": false}, {"data": [0.9893520322036099, 500, 1500, "06 POST /api/checkout"], "isController": false}, {"data": [0.9821672188657182, 500, 1500, "07 GET /api/orders/my-orders"], "isController": false}]}, function(index, item){
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
    createTable($("#statisticsTable"), {"supportsControllersDiscrimination": true, "overall": {"data": ["Total", 108740, 0, 0.0, 103.9568144197171, 0, 1005, 225.0, 556.0, 641.0, 832.0, 302.05219942000645, 979.8345610830019, 96.47110691825645], "isController": false}, "titles": ["Label", "#Samples", "FAIL", "Error %", "Average", "Min", "Max", "Median", "90th pct", "95th pct", "99th pct", "Transactions/s", "Received", "Sent"], "items": [{"data": ["02 GET /api/products?search", 15701, 0, 0.0, 88.01770587860626, 0, 768, 24.0, 279.0, 381.89999999999964, 540.9799999999996, 43.86709953565302, 21.46566074888523, 8.606380959922832], "isController": false}, {"data": ["04 POST /api/cart", 15419, 0, 0.0, 48.50269148453221, 0, 423, 14.0, 152.0, 194.0, 267.0, 43.51740526871342, 12.494255028322016, 17.911241852304993], "isController": false}, {"data": ["TC-01 AUTH (auth-heavy)", 15881, 0, 0.0, 109.34651470310426, 0, 769, 32.0, 349.0, 443.0, 585.0, 44.09269989699394, 27.71508576694394, 11.066234251491645], "isController": true}, {"data": ["TC-03 TRANSACTION (transactional)", 15393, 0, 0.0, 438.13350224127856, 2, 2560, 139.0, 1369.0, 1736.0, 2143.0599999999995, 43.43029653246057, 925.5516973335708, 69.89773302379878], "isController": true}, {"data": ["01 POST /api/login", 15881, 0, 0.0, 109.34645173477713, 0, 769, 32.0, 349.0, 443.0, 585.0, 44.11388888888889, 27.728404405381944, 11.071552191840278], "isController": false}, {"data": ["TC-02 BROWSE (read-heavy)", 15682, 0, 0.0, 179.2971559750037, 1, 1221, 85.0, 520.0, 686.0, 909.0, 43.793826639894775, 41.026380940595445, 16.59617907537135], "isController": true}, {"data": ["05 POST /api/apply-coupon", 15415, 0, 0.0, 165.57950048653873, 0, 1005, 50.0, 520.0, 672.0, 845.0, 43.499486415405286, 17.064201447384388, 18.034830806327815], "isController": false}, {"data": ["03 GET /api/products/{id}", 15529, 0, 0.0, 92.26080236975994, 0, 779, 28.0, 283.0, 379.0, 541.0, 43.652913098966096, 19.72501532026379, 8.057031812211516], "isController": false}, {"data": ["06 POST /api/checkout", 15402, 0, 0.0, 109.60706401766014, 2, 848, 38.0, 328.0, 416.0, 558.0, 43.46930308563752, 13.383745253218144, 19.029216852433823], "isController": false}, {"data": ["07 GET /api/orders/my-orders", 15393, 0, 0.0, 114.63717274085612, 0, 797, 35.0, 358.0, 457.0, 597.0, 43.4457415101156, 882.9875929507218, 15.009405985043918], "isController": false}]}, function(index, item){
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
    createTable($("#top5ErrorsBySamplerTable"), {"supportsControllersDiscrimination": false, "overall": {"data": ["Total", 108740, 0, "", "", "", "", "", "", "", "", "", ""], "isController": false}, "titles": ["Sample", "#Samples", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors"], "items": [{"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}]}, function(index, item){
        return item;
    }, [[0, 0]], 0);

});
