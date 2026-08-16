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
    createTable($("#apdexTable"), {"supportsControllersDiscrimination": true, "overall": {"data": [0.9114369454240946, 500, 1500, "Total"], "isController": false}, "titles": ["Apdex", "T (Toleration threshold)", "F (Frustration threshold)", "Label"], "items": [{"data": [0.9948502614482649, 500, 1500, "02 GET /api/products?search"], "isController": false}, {"data": [1.0, 500, 1500, "04 POST /api/cart"], "isController": false}, {"data": [0.9890230515916575, 500, 1500, "TC-01 AUTH (auth-heavy)"], "isController": true}, {"data": [0.5305129473857826, 500, 1500, "TC-03 TRANSACTION (transactional)"], "isController": true}, {"data": [0.9890230515916575, 500, 1500, "01 POST /api/login"], "isController": false}, {"data": [0.7742294248490627, 500, 1500, "TC-02 BROWSE (read-heavy)"], "isController": true}, {"data": [0.850398827934234, 500, 1500, "05 POST /api/apply-coupon"], "isController": false}, {"data": [0.9919833253166587, 500, 1500, "03 GET /api/products/{id}"], "isController": false}, {"data": [0.9954799474030244, 500, 1500, "06 POST /api/checkout"], "isController": false}, {"data": [0.9896091044037605, 500, 1500, "07 GET /api/orders/my-orders"], "isController": false}]}, function(index, item){
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
    createTable($("#statisticsTable"), {"supportsControllersDiscrimination": true, "overall": {"data": ["Total", 43363, 0, 0.0, 228.51730738186868, 0, 958, 251.0, 474.0, 560.0, 687.0, 180.92945240916603, 274.54502980425, 57.68410542787314], "isController": false}, "titles": ["Label", "#Samples", "FAIL", "Error %", "Average", "Min", "Max", "Median", "90th pct", "95th pct", "99th pct", "Transactions/s", "Received", "Sent"], "items": [{"data": ["02 GET /api/products?search", 6311, 0, 0.0, 218.93931231183652, 0, 640, 229.0, 401.0, 437.0, 502.8800000000001, 26.567597718327054, 13.000846714569871, 5.212363545591362], "isController": false}, {"data": ["04 POST /api/cart", 6148, 0, 0.0, 101.96763175016277, 0, 354, 102.0, 190.0, 209.54999999999927, 255.0, 26.363184164937138, 7.569117328604998, 10.850746556662836], "isController": false}, {"data": ["TC-01 AUTH (auth-heavy)", 6377, 0, 0.0, 236.26893523600418, 0, 650, 246.0, 428.0, 468.0, 545.0, 26.587561340676842, 16.711934676869614, 6.672854750540965], "isController": true}, {"data": ["TC-03 TRANSACTION (transactional)", 6063, 0, 0.0, 918.6039914233901, 4, 2087, 978.0, 1583.0, 1689.0, 1943.7199999999993, 25.91435397904797, 238.5956693740036, 41.7070821561529], "isController": true}, {"data": ["01 POST /api/login", 6377, 0, 0.0, 236.26862160890627, 0, 650, 246.0, 428.0, 468.0, 545.0, 26.607640569454414, 16.724555720048148, 6.677894166357211], "isController": false}, {"data": ["TC-02 BROWSE (read-heavy)", 6294, 0, 0.0, 439.1437877343499, 1, 1148, 473.0, 776.0, 830.0, 952.1000000000004, 26.56581729774904, 24.89325291974962, 10.070838651122104], "isController": true}, {"data": ["05 POST /api/apply-coupon", 6143, 0, 0.0, 354.73807585870065, 0, 958, 370.0, 631.0, 670.0, 786.5599999999995, 26.341856665651814, 10.33356081530898, 10.921241197315215], "isController": false}, {"data": ["03 GET /api/products/{id}", 6237, 0, 0.0, 222.65383998717346, 0, 701, 231.0, 407.0, 446.0, 533.0, 26.50444715471339, 11.976150758385426, 4.891934093985187], "isController": false}, {"data": ["06 POST /api/checkout", 6084, 0, 0.0, 222.3895463510852, 2, 671, 229.0, 402.0, 453.75, 497.0, 26.092102893118444, 8.021743050522357, 11.421958326989715], "isController": false}, {"data": ["07 GET /api/orders/my-orders", 6063, 0, 0.0, 242.9526636978393, 0, 700, 253.0, 437.0, 474.0, 588.7199999999993, 26.002487455504564, 213.7469987361689, 8.98320230411288], "isController": false}]}, function(index, item){
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
    createTable($("#top5ErrorsBySamplerTable"), {"supportsControllersDiscrimination": false, "overall": {"data": ["Total", 43363, 0, "", "", "", "", "", "", "", "", "", ""], "isController": false}, "titles": ["Sample", "#Samples", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors", "Error", "#Errors"], "items": [{"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}, {"data": [], "isController": false}]}, function(index, item){
        return item;
    }, [[0, 0]], 0);

});
