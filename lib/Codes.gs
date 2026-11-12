/*
 * // const SPREADSHEET_ID = "1YFyW1aqcMM6UhruDI5f5GUJui5kmKuKtKa0XWhk0Y";
 * // const DRIVE_FOLDER_ID = "1aqcM1aqcMM6UhruDI5f5GUJui5kmKuKtKa0XWKa0XW";
 * // const SECRET_API_KEY = "1aqcMM6U1aqcMM6UhruDI5f5GUJui5kmKuKtKa0XWmKuKtKa0XW";
 *
 *
 *
 * // Name of the sheet where customer star-feedback is stored (created automatically)
 * const FEEDBACK_SHEET_NAME = "feedback";
 *
 * function getSpreadsheet() {
 *  return SpreadsheetApp.openById(SPREADSHEET_ID);
 * }
 *
 * function responseJSON(payload) {
 *  return ContentService.createTextOutput(JSON.stringify(payload))
 *    .setMimeType(ContentService.MimeType.JSON);
 * }
 *
 * function convertAndroidPathsToDriveUrls(pathsString) {
 *  if (!pathsString || String(pathsString).trim() === "") return "";
 *  try {
 *    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
 *    const rawPaths = String(pathsString).split(",");
 *    const validUrls = [];
 *
 *    for (let i = 0; i < rawPaths.length; i++) {
 *      let item = rawPaths[i].trim();
 *      if (!item) continue;
 *
 *      // Preserve <receipt> reference tags exactly as they are
 *      if (item.startsWith("<receipt>") && item.endsWith("</receipt>")) {
 *        validUrls.push(item);
 *        continue;
 *      }
 *
 *      // Preserve already valid HTTP/HTTPS URLs
 *      if (item.startsWith("http://") || item.startsWith("https://")) {
 *        validUrls.push(item);
 *        continue;
 *      }
 *
 *      // Process actual image filenames into Google Drive URLs
 *      let fileName = item.split("/").pop();
 *      let files = folder.getFilesByName(fileName);
 *      if (files.hasNext()) {
 *        validUrls.push("https://lh3.googleusercontent.com/d/" + files.next().getId());
 *      }
 *    }
 *    return validUrls.join(",");
 *  } catch (err) {
 *    return pathsString;
 *  }
 * }
 *
 * // ==========================================
 * // NEW AUTOMATED 4-DAY ROLLING BACKUP SYSTEM
 * // ==========================================
 * function performDailyBackupIfNeeded() {
 *  // Use a lock so simultaneous requests don't create multiple backups for the same day
 *  const lock = LockService.getScriptLock();
 *  if (!lock.tryLock(5000)) return;
 *
 *  try {
 *    const scriptProperties = PropertiesService.getScriptProperties();
 *    const lastBackupDate = scriptProperties.getProperty("LAST_BACKUP_DATE");
 *
 *    // Format current date in IST Timezone
 *    const todayStr = Utilities.formatDate(new Date(), "Asia/Kolkata", "yyyy-MM-dd");
 *
 *    // If we already backed up today, do nothing and exit
 *    if (lastBackupDate === todayStr) {
 *      return;
 *    }
 *
 *    const ss = getSpreadsheet();
 *    const originalFile = DriveApp.getFileById(SPREADSHEET_ID);
 *    // Find the folder where the original sheet lives
 *    const folder = originalFile.getParents().hasNext() ? originalFile.getParents().next() : DriveApp.getRootFolder();
 *
 *    // 1. Create a copy for today
 *    const backupName = "Backup_" + todayStr + "_" + ss.getName();
 *    originalFile.makeCopy(backupName, folder);
 *
 *    // 2. Clean up old backups (keep only the last 4 days)
 *    const files = folder.getFiles();
 *    const backupFiles = [];
 *
 *    while (files.hasNext()) {
 *      const file = files.next();
 *      const name = file.getName();
 *      // Identify valid backup files for this specific sheet
 *      if (name.startsWith("Backup_") && name.endsWith("_" + ss.getName())) {
 *        const datePart = name.split("_")[1]; // Extract the YYYY-MM-DD part
 *        backupFiles.push({ file: file, date: datePart });
 *      }
 *    }
 *
 *    // Sort newest to oldest
 *    backupFiles.sort((a, b) => {
 *      if (a.date < b.date) return 1;
 *      if (a.date > b.date) return -1;
 *      return 0;
 *    });
 *
 *    // Trashing older files past the 4-day limit
 *    const MAX_BACKUPS = 4;
 *    for (let i = MAX_BACKUPS; i < backupFiles.length; i++) {
 *      backupFiles[i].file.setTrashed(true);
 *    }
 *
 *    // Update the system property to flag today's backup as complete
 *    scriptProperties.setProperty("LAST_BACKUP_DATE", todayStr);
 *
 *  } catch (e) {
 *    console.error("Backup failed: " + e.toString());
 *  } finally {
 *    lock.releaseLock();
 *  }
 * }
 *
 * // ==========================================
 * // CUSTOMER FEEDBACK (STAR RATING) -> "feedback" sheet, saved date & time wise
 * // bill.html calls:  ?action=feedback&phone=...&name=...&rating=1..5
 * // * ONE feedback per customer, kept forever on the server (same on every browser/device)
 * // * Every new feedback is a NEW row at the bottom (oldest -> newest)
 * // * The bill lookup (doGet) also returns the customer's saved feedback inside customer.feedback
 * // * The app can download the full list with the secret key: action "fetch_feedbacks"
 * // ==========================================
 * const FEEDBACK_HEADERS = ["Date & Time", "Customer Name", "Phone", "Rating (out of 5)", "Customer ID"];
 * const FEEDBACK_DATE_FORMAT = "dd-MM-yyyy hh:mm:ss a";
 *
 * // Last 10 digits of a phone number (same matching rule the bill lookup uses)
 * function lastTenDigits(value) {
 *  let d = String(value === null || value === undefined ? "" : value).replace(/\D/g, "");
 *  if (d.length >= 10) d = d.slice(-10);
 *  return d;
 * }
 *
 * // Sheet date cell -> text such as "11-10-2026 09:47:12 PM" (the Indian time that was stored)
 * function feedbackDateText(ss, value) {
 *  if (value instanceof Date) return Utilities.formatDate(value, ss.getSpreadsheetTimeZone(), FEEDBACK_DATE_FORMAT);
 *  return String(value === null || value === undefined ? "" : value);
 * }
 *
 * // Creates the sheet if needed. An older sheet that still has a "Stars" column is cleaned up automatically.
 * function getOrCreateFeedbackSheet(ss) {
 *  let sheet = ss.getSheetByName(FEEDBACK_SHEET_NAME);
 *  if (!sheet) sheet = ss.insertSheet(FEEDBACK_SHEET_NAME);
 *  if (sheet.getLastRow() === 0) {
 *    sheet.getRange(1, 1, 1, FEEDBACK_HEADERS.length)
 *      .setValues([FEEDBACK_HEADERS])
 *      .setFontWeight("bold")
 *      .setBackground("#e2e8f0");
 *    sheet.setFrozenRows(1);
 *    sheet.setColumnWidth(1, 180);
 *    sheet.setColumnWidth(2, 180);
 *    sheet.setColumnWidth(3, 120);
 *    sheet.setColumnWidth(4, 130);
 *    sheet.setColumnWidth(5, 120);
 *  } else {
 *    const head = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(h => String(h).trim());
 *    const starsAt = head.indexOf("Stars");
 *    if (starsAt >= 0) sheet.deleteColumn(starsAt + 1); // remove the old Stars column, other data stays
 *  }
 *  return sheet;
 * }
 *
 * // Reads every saved feedback (oldest -> newest). Finds columns by their header names,
 * // so it works for both the old layout (with Stars) and the new one.
 * function getFeedbackRecords(ss) {
 *  const sheet = ss.getSheetByName(FEEDBACK_SHEET_NAME);
 *  if (!sheet || sheet.getLastRow() < 2) return [];
 *  const data = sheet.getDataRange().getValues();
 *  const head = data[0].map(h => String(h).trim());
 *  const col = function (title, fallback) { const i = head.indexOf(title); return i >= 0 ? i : fallback; };
 *  const cDate = col("Date & Time", 0), cName = col("Customer Name", 1), cPhone = col("Phone", 2),
 *        cRating = col("Rating (out of 5)", 3), cId = col("Customer ID", 4);
 *  const out = [];
 *  for (let i = 1; i < data.length; i++) {
 *    const r = data[i];
 *    const phone = String(r[cPhone] === null || r[cPhone] === undefined ? "" : r[cPhone]).trim();
 *    const id = String(r[cId] === null || r[cId] === undefined ? "" : r[cId]).trim();
 *    if (phone === "" && id === "") continue; // blank row
 *    out.push({
 *      customerId: id,
 *      name: String(r[cName] === null || r[cName] === undefined ? "" : r[cName]),
 *      phone: phone,
 *      rating: Number(r[cRating]) || 0,
 *      date: feedbackDateText(ss, r[cDate])
 *    });
 *  }
 *  return out;
 * }
 *
 * // Finds the saved feedback of one customer (matched by phone OR by customer ID)
 * function findFeedbackFor(records, customerId, phone10) {
 *  const idText = String(customerId === null || customerId === undefined ? "" : customerId).trim();
 *  for (let i = 0; i < records.length; i++) {
 *    const samePhone = phone10 !== "" && lastTenDigits(records[i].phone) === phone10;
 *    const sameId = idText !== "" && records[i].customerId === idText;
 *    if (samePhone || sameId) return records[i];
 *  }
 *  return null;
 * }
 *
 * // Used by the bill lookup: {rating, date} if this customer already gave feedback, otherwise null.
 * // Never throws - a problem here must never break the bill page.
 * function getCustomerFeedback(ss, customerId, phone) {
 *  try {
 *    const found = findFeedbackFor(getFeedbackRecords(ss), customerId, lastTenDigits(phone));
 *    return found ? { rating: found.rating, date: found.date } : null;
 *  } catch (err) {
 *    return null;
 *  }
 * }
 *
 * function handleFeedback(e) {
 *  const lock = LockService.getScriptLock();
 *  let locked = false;
 *  try {
 *    const p = e.parameter || {};
 *
 *    // 1) Validate the rating (must be a whole number 1-5)
 *    const rating = Number(p.rating);
 *    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
 *      return responseJSON({ status: "error", message: "Invalid rating." });
 *    }
 *
 *    // 2) The phone must belong to a real customer (blocks random/fake submissions)
 *    const phone10 = lastTenDigits(p.phone);
 *    if (!phone10) return responseJSON({ status: "error", message: "Phone required." });
 *
 *    const ss = getSpreadsheet();
 *    const custSheet = ss.getSheetByName("customers");
 *    if (!custSheet) return responseJSON({ status: "error", message: "'customers' missing." });
 *
 *    const custData = custSheet.getDataRange().getValues();
 *    let customer = null;
 *    for (let i = 1; i < custData.length; i++) {
 *      if (lastTenDigits(custData[i][2]) === phone10) {
 *        customer = { id: custData[i][0], name: custData[i][1], phone: custData[i][2] };
 *        break;
 *      }
 *    }
 *    if (!customer) return responseJSON({ status: "not_found", message: "Customer not found." });
 *
 *    // Name comes from your customers sheet (trusted); falls back to the name the page sent
 *    const name = String(customer.name || p.name || "").trim().substring(0, 100);
 *
 *    // 3) Current date & time in IST. Stored as a REAL date-time (sortable / filterable in Sheets)
 *    //    and shown the same way even if the spreadsheet itself is set to another time zone.
 *    const istNow = Utilities.formatDate(new Date(), "Asia/Kolkata", "yyyy-MM-dd HH:mm:ss");
 *    const when = Utilities.parseDate(istNow, ss.getSpreadsheetTimeZone(), "yyyy-MM-dd HH:mm:ss");
 *
 *    // 4) Lock = two submissions at the same moment can never both get in or overwrite each other.
 *    lock.waitLock(15000);
 *    locked = true;
 *    const sheet = getOrCreateFeedbackSheet(ss);
 *
 *    // ONE FEEDBACK PER CUSTOMER (by phone or ID). The first one is kept; the stored one is sent back
 *    // so the page can show it, even when the customer opens the bill on a different browser/device.
 *    const already = findFeedbackFor(getFeedbackRecords(ss), customer.id, phone10);
 *    if (already) {
 *      return responseJSON({
 *        status: "already_submitted",
 *        message: "Feedback already received.",
 *        feedback: { rating: already.rating, date: already.date }
 *      });
 *    }
 *
 *    const row = sheet.getLastRow() + 1;
 *    const range = sheet.getRange(row, 1, 1, FEEDBACK_HEADERS.length);
 *    // "@" = plain text: keeps phone numbers intact and stops any name starting with = from becoming a formula
 *    range.setNumberFormats([[FEEDBACK_DATE_FORMAT, "@", "@", "0", "@"]]);
 *    range.setValues([[when, name, String(customer.phone).trim(), rating, String(customer.id)]]);
 *
 *    return responseJSON({
 *      status: "success",
 *      message: "Feedback saved.",
 *      feedback: { rating: rating, date: Utilities.formatDate(when, ss.getSpreadsheetTimeZone(), FEEDBACK_DATE_FORMAT) }
 *    });
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: "Feedback failed: " + error.toString() });
 *  } finally {
 *    if (locked) lock.releaseLock();
 *  }
 * }
 *
 * // ==========================================
 * // APP MODULE: all feedback list (needs the SECRET API KEY)
 * //   POST (JSON body):  { "action": "fetch_feedbacks", "apiKey": "<SECRET_API_KEY>" }
 * //   GET  (for testing): ?action=fetch_feedbacks&apiKey=<SECRET_API_KEY>
 * // Returns newest feedback first, plus total count, average and how many 1-5 star ratings.
 * // ==========================================
 * function fetchAllFeedbacks() {
 *  try {
 *    const ss = getSpreadsheet();
 *    const records = getFeedbackRecords(ss);
 *
 *    const distribution = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
 *    let counted = 0, total = 0;
 *    for (let i = 0; i < records.length; i++) {
 *      const r = records[i].rating;
 *      if (r >= 1 && r <= 5) { distribution[String(r)]++; counted++; total += r; }
 *    }
 *
 *    const feedbacks = records.slice().reverse().map(function (r) {
 *      return { customerId: r.customerId, name: r.name, phone: r.phone, rating: r.rating, date: r.date };
 *    });
 *
 *    return responseJSON({
 *      status: "success",
 *      count: records.length,
 *      average: counted ? Math.round((total / counted) * 10) / 10 : 0,
 *      distribution: distribution,
 *      feedbacks: feedbacks
 *    });
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: "Fetch feedbacks failed: " + error.toString() });
 *  }
 * }
 *
 * function doGet(e) {
 *  try {
 *    // Feedback requests are handled first (they carry no apiKey, so they must not reach the checks below)
 *    if (e && e.parameter && e.parameter.action === "feedback") return handleFeedback(e);
 *    // App: full feedback list (secret key required)
 *    if (e && e.parameter && e.parameter.action === "fetch_feedbacks") {
 *      if (e.parameter.apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Invalid API Key." });
 *      return fetchAllFeedbacks();
 *    }
 *
 *    const phone = e.parameter ? e.parameter.phone : null;
 *    const bill = e.parameter ? e.parameter.bill : null;
 *    const apiKey = e.parameter ? e.parameter.apiKey : null;
 *
 *    if (!phone && !bill) return responseJSON({ status: "error", message: "Phone or Bill required." });
 *    if (phone && apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Invalid API Key." });
 *
 *    const ss = getSpreadsheet();
 *    const custSheet = ss.getSheetByName("customers");
 *    if (!custSheet) return responseJSON({ status: "error", message: "'customers' missing." });
 *
 *    const custData = custSheet.getDataRange().getValues();
 *    let customer = null;
 *    let customerId = null;
 *
 *    if (bill) {
 *      let cleanBill = String(bill).replace(/\D/g, '');
 *      if (cleanBill.length >= 10) cleanBill = cleanBill.slice(-10);
 *      for (let i = 1; i < custData.length; i++) {
 *        let sheetPhone = String(custData[i][2]).replace(/\D/g, '');
 *        if (sheetPhone.length >= 10) sheetPhone = sheetPhone.slice(-10);
 *        if (sheetPhone === cleanBill && cleanBill !== '') {
 *          customerId = custData[i][0];
 *          customer = { id: customerId, name: custData[i][1], phone: custData[i][2], address: custData[i][3], due: custData[i][4], images: convertAndroidPathsToDriveUrls(custData[i][5]), createdAt: custData[i][6], dueHistory: custData[i][7] };
 *          break;
 *        }
 *      }
 *    } else {
 *      for (let i = 1; i < custData.length; i++) {
 *        if (String(custData[i][2]).trim() === String(phone).trim()) {
 *          customerId = custData[i][0];
 *          customer = { id: customerId, name: custData[i][1], phone: custData[i][2], address: custData[i][3], due: custData[i][4], images: convertAndroidPathsToDriveUrls(custData[i][5]), createdAt: custData[i][6], dueHistory: custData[i][7] };
 *          break;
 *        }
 *      }
 *    }
 *
 *    if (!customer) return responseJSON({ status: "not_found", message: "Not found." });
 *
 *    // Feedback this customer already gave (null if none) - so the bill page shows it on every browser/device
 *    customer.feedback = getCustomerFeedback(ss, customerId, customer.phone);
 *
 *    const transSheet = ss.getSheetByName("transactions");
 *    const transactions = [];
 *    if (transSheet) {
 *      const transData = transSheet.getDataRange().getValues();
 *      for (let i = 1; i < transData.length; i++) {
 *        if (String(transData[i][1]) === String(customerId)) {
 *            transactions.push({ id: transData[i][0], amount: transData[i][2], date: transData[i][3], note: transData[i][4] });
 *        }
 *      }
 *    }
 *
 *    const receiptSheet = ss.getSheetByName("receipt_calculations");
 *    const receiptCalculations = [];
 *    if (receiptSheet) {
 *      const receiptData = receiptSheet.getDataRange().getValues();
 *      if (receiptData.length > 0) {
 *        const headers = receiptData[0];
 *
 *        let idIdx = headers.indexOf("id") !== -1 ? headers.indexOf("id") : 0;
 *        let custIdIdx = headers.indexOf("customerId") !== -1 ? headers.indexOf("customerId") :
 *                       (headers.indexOf("customer_id") !== -1 ? headers.indexOf("customer_id") : 1);
 *        let jsonIdx = headers.indexOf("calculationJson") !== -1 ? headers.indexOf("calculationJson") : 2;
 *        let dateIdx = headers.indexOf("datetime") !== -1 ? headers.indexOf("datetime") : 3;
 *
 *        for (let i = 1; i < receiptData.length; i++) {
 *          if (String(receiptData[i][custIdIdx]) === String(customerId)) {
 *            let jsonString = receiptData[i][jsonIdx];
 *            let skip = false;
 *
 *            try {
 *              if (jsonString && typeof jsonString === 'string') {
 *                let parsedJson = JSON.parse(jsonString);
 *                if (parsedJson && parsedJson.type === "draft") {
 *                  skip = true;
 *                }
 *              }
 *            } catch (e) {
 *              // Ignore standard parse errors, push data anyway to be safe
 *            }
 *
 *            if (!skip) {
 *              receiptCalculations.push({
 *                  id: receiptData[i][idIdx],
 *                  calculationJson: jsonString,
 *                  datetime: receiptData[i][dateIdx]
 *              });
 *            }
 *          }
 *        }
 *      }
 *    }
 *
 *    const msgSheet = ss.getSheetByName("messages");
 *    const messages = [];
 *    if (msgSheet) {
 *      const msgData = msgSheet.getDataRange().getValues();
 *      for (let i = 1; i < msgData.length; i++) {
 *        if (String(msgData[i][1]) === String(customerId)) {
 *            messages.push({ id: msgData[i][0], text: msgData[i][2], date: msgData[i][3] });
 *        }
 *      }
 *    }
 *
 *    return responseJSON({ status: "success", data: { customer, transactions, receipt_calculations: receiptCalculations, messages } });
 *
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: error.toString() });
 *  }
 * }
 *
 * function doPost(e) {
 *  try {
 *    if (!e.postData || !e.postData.contents) return responseJSON({ status: "error", message: "No payload." });
 *    const parsedData = JSON.parse(e.postData.contents);
 *
 *    // Check API Key first before proceeding
 *    if (parsedData.apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Unauthorized action. Invalid API Key." });
 *
 *    // ===============================================
 *    // Trigger daily backup before modifying anything
 *    // ===============================================
 *    performDailyBackupIfNeeded();
 *
 *    switch (parsedData.action) {
 *      case "full_text_backup": return handleFullTextBackup(parsedData);
 *      case "upload_image": return uploadImage(parsedData);
 *      case "delete_images": return deleteImages(parsedData);
 *      case "add_customer": return saveCustomerAndMessage(parsedData);
 *      case "add_expense": return addExpense(parsedData);
 *      case "delete_expense": return deleteExpense(parsedData);
 *      case "add_order": return addOrder(parsedData);
 *      case "add_bulk_orders": return addBulkOrders(parsedData);
 *      case "delete_orders_bulk": return delete_orders_bulk(parsedData);
 *      case "delete_order": return deleteOrder(parsedData);
 *      case "add_temp_customer": return addTempCustomer(parsedData);
 *      case "delete_temp_customer": return deleteTempCustomer(parsedData);
 *      case "fetch_full_database": return fetchFullDatabase();
 *      case "fetch_feedbacks": return fetchAllFeedbacks();
 *      default: return responseJSON({ status: "error", message: "Unknown action trigger" });
 *    }
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: error.toString() });
 *  }
 * }
 *
 * // function handleFullTextBackup(data) {
 * //   try {
 * //     const ss = getSpreadsheet();
 * //     const db = data.database;
 * //     const activeImages = data.active_images || [];
 * //
 * //     if (db && typeof db === "object") {
 * //       for (let tableName in db) {
 * //         if (!db.hasOwnProperty(tableName)) continue;
 * //         let rows = db[tableName];
 * //         let sheet = ss.getSheetByName(tableName) || ss.insertSheet(tableName);
 * //         sheet.clear();
 * //
 * //         if (Array.isArray(rows) && rows.length > 0) {
 * //           let headers = Object.keys(rows[0]);
 * //           let matrix = [headers];
 * //           for (let i = 0; i < rows.length; i++) {
 * //             matrix.push(headers.map(h => {
 * //               let val = rows[i][h];
 * //               return (typeof val === "object" && val !== null) ? JSON.stringify(val) : (val === null || val === undefined ? "" : val);
 * //             }));
 * //           }
 * //           sheet.getRange(1, 1, matrix.length, headers.length).setValues(matrix);
 * //         }
 * //       }
 * //     }
 * //
 * //     const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
 * //     const driveFiles = folder.getFiles();
 * //     const driveFileNames = new Set();
 * //     const activeImageSet = new Set(activeImages);
 * //     let trashedCount = 0;
 * //
 * //     while (driveFiles.hasNext()) {
 * //       let file = driveFiles.next();
 * //       let fileName = file.getName();
 * //
 * //       if (activeImageSet.has(fileName)) {
 * //         driveFileNames.add(fileName);
 * //       } else {
 * //         file.setTrashed(true);
 * //         trashedCount++;
 * //       }
 * //     }
 * //
 * //     const missingImages = [];
 * //     for (let i = 0; i < activeImages.length; i++) {
 * //       if (!driveFileNames.has(activeImages[i])) {
 * //         missingImages.push(activeImages[i]);
 * //       }
 * //     }
 * //
 * //     return responseJSON({
 * //       status: "success",
 * //       message: "Database synced.",
 * //       trashed_count: trashedCount,
 * //       missing_images: missingImages
 * //     });
 * //   } catch (error) {
 * //     return responseJSON({ status: "error", message: "Full backup failed: " + error.toString() });
 * //   }
 * // }
 *
 * function handleFullTextBackup(data) {
 *  try {
 *    const ss = getSpreadsheet();
 *    const db = data.database;
 *    const activeImages = data.active_images || [];
 *
 *    if (db && typeof db === "object") {
 *      for (let tableName in db) {
 *        if (!db.hasOwnProperty(tableName)) continue;
 *        let rows = db[tableName];
 *        let sheet = ss.getSheetByName(tableName) || ss.insertSheet(tableName);
 *
 *        if (Array.isArray(rows) && rows.length > 0) {
 *          // We have data: Clear the sheet and rewrite headers + data
 *          sheet.clear();
 *
 *          let headers = Object.keys(rows[0]);
 *          let matrix = [headers];
 *          for (let i = 0; i < rows.length; i++) {
 *            matrix.push(headers.map(h => {
 *              let val = rows[i][h];
 *              return (typeof val === "object" && val !== null) ? JSON.stringify(val) : (val === null || val === undefined ? "" : val);
 *            }));
 *          }
 *          sheet.getRange(1, 1, matrix.length, headers.length).setValues(matrix);
 *        } else {
 *          // Table is empty: Keep headers in row 1, but clear all old data from row 2 downwards
 *          let lastRow = sheet.getLastRow();
 *          let lastCol = sheet.getLastColumn();
 *          if (lastRow > 1 && lastCol > 0) {
 *            sheet.getRange(2, 1, lastRow - 1, lastCol).clearContent();
 *          }
 *        }
 *      }
 *    }
 *
 *    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
 *    const driveFiles = folder.getFiles();
 *    const driveFileNames = new Set();
 *    const activeImageSet = new Set(activeImages);
 *    let trashedCount = 0;
 *
 *    while (driveFiles.hasNext()) {
 *      let file = driveFiles.next();
 *      let fileName = file.getName();
 *
 *      if (activeImageSet.has(fileName)) {
 *        driveFileNames.add(fileName);
 *      } else {
 *        file.setTrashed(true);
 *        trashedCount++;
 *      }
 *    }
 *
 *    const missingImages = [];
 *    for (let i = 0; i < activeImages.length; i++) {
 *      if (!driveFileNames.has(activeImages[i])) {
 *        missingImages.push(activeImages[i]);
 *      }
 *    }
 *
 *    return responseJSON({
 *      status: "success",
 *      message: "Database synced.",
 *      trashed_count: trashedCount,
 *      missing_images: missingImages
 *    });
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: "Full backup failed: " + error.toString() });
 *  }
 * }
 *
 *
 *
 *
 *
 * function uploadImage(data) {
 *  try {
 *    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
 *    const contentType = data.mimeType || "image/jpeg";
 *    const fileName = data.filename || "image.jpg";
 *
 *    // Clean base64 string to ensure valid decoding
 *    let base64Str = data.base64 || "";
 *    if (base64Str.indexOf(",") !== -1) {
 *      base64Str = base64Str.split(",")[1];
 *    }
 *
 *    const bytes = Utilities.base64Decode(base64Str);
 *    const blob = Utilities.newBlob(bytes, contentType, fileName);
 *
 *    // Trash old file with same name to prevent duplicates
 *    const existingFiles = folder.getFilesByName(fileName);
 *    while (existingFiles.hasNext()) {
 *      existingFiles.next().setTrashed(true);
 *    }
 *
 *    // Safely generate the file from the binary blob
 *    const file = folder.createFile(blob);
 *    try {
 *      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
 *    } catch (e) {}
 *
 *    return responseJSON({ status: "success", fileId: file.getId() });
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: "Upload failed: " + error.toString() });
 *  }
 * }
 *
 *
 *
 * function fetchFullDatabase() {
 *  try {
 *    const ss = getSpreadsheet();
 *    const sheets = ss.getSheets();
 *    const db = {};
 *
 *    for (let i = 0; i < sheets.length; i++) {
 *      let sheetName = sheets[i].getName();
 *      if (sheetName === FEEDBACK_SHEET_NAME) continue; // feedback log is not part of the app database
 *      let data = sheets[i].getDataRange().getValues();
 *      if (data.length < 2) continue; // Skip empty sheets
 *
 *      let headers = data[0];
 *      let rows = [];
 *      for (let j = 1; j < data.length; j++) {
 *        let obj = {};
 *        for (let k = 0; k < headers.length; k++) {
 *          obj[headers[k]] = data[j][k];
 *        }
 *        rows.push(obj);
 *      }
 *      db[sheetName] = rows;
 *    }
 *    return responseJSON({ status: "success", database: db });
 *  } catch (error) {
 *    return responseJSON({ status: "error", message: error.toString() });
 *  }
 * }
 *
 * // -----------------------------------------------------
 * // Placeholder functions as requested (to be filled later)
 * // -----------------------------------------------------
 * function deleteImages(data) {}
 * function saveCustomerAndMessage(data) {}
 * function addExpense(data) {}
 * function deleteExpense(data) {}
 * function addOrder(data) {}
 * function addBulkOrders(data) {}
 * function delete_orders_bulk(data) {}
 * function deleteOrder(data) {}
 * function addTempCustomer(data) {}
 * function deleteTempCustomer(data) {}
 *
 *
 *
 *
 *
 *
 * */



// =====================================================================
// PASTE YOUR REAL VALUES HERE (the same ones you had in your old script)
// =====================================================================
// const SPREADSHEET_ID = "PASTE_YOUR_SPREADSHEET_ID";
// const DRIVE_FOLDER_ID = "PASTE_YOUR_DRIVE_FOLDER_ID";
// const SECRET_API_KEY = "PASTE_YOUR_SECRET_API_KEY";

// Name of the sheet where customer star-feedback is stored (created automatically)
const FEEDBACK_SHEET_NAME = "feedback";

// =====================================================================
// SPEED SETTINGS
// =====================================================================
// How long a customer's finished bill is kept ready in memory (seconds).
// Any change made from the app (doPost) or a new feedback clears it immediately.
// If you edit the Google Sheet by hand, the customer sees the change after this time.
const BILL_CACHE_SECONDS = 600; // 10 minutes

// How long "image file name -> Drive file id" is remembered (max allowed is 21600 = 6 hours)
const IMAGE_ID_CACHE_SECONDS = 21600;

// Image width used for the bill page. Original phone photos are several MB each and are the
// biggest cause of "slow receipt". 1200 is still sharp for reading a receipt.
// Set to 0 to give the full-size original image like before.
const IMAGE_WIDTH = 1200;

// =====================================================================
// BASIC HELPERS
// =====================================================================
function getSpreadsheet() {
  return SpreadsheetApp.openById(SPREADSHEET_ID);
}

function responseJSON(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
  .setMimeType(ContentService.MimeType.JSON);
}

// =====================================================================
// CACHE HELPERS
// =====================================================================
// Version number inside the cache key. Changing it instantly "forgets" every saved bill.
function getCacheVersion() {
  const cache = CacheService.getScriptCache();
  let v = cache.get("cache_version");
  if (!v) {
    v = String(Date.now());
    cache.put("cache_version", v, 21600);
  }
  return v;
}

function bumpCacheVersion() {
  try {
    CacheService.getScriptCache().put("cache_version", String(Date.now()), 21600);
  } catch (err) {}
}

// CacheService allows ~100KB per key, so big bills are split into pieces.
function cachePutBig(cache, key, str, ttl) {
  try {
    const SIZE = 90000;
    if (str.length > 900000) return; // too big, just skip caching
    const n = Math.ceil(str.length / SIZE);
    const obj = {};
    for (let i = 0; i < n; i++) obj[key + "_" + i] = str.substr(i * SIZE, SIZE);
    obj[key + "_n"] = String(n);
    cache.putAll(obj, ttl);
  } catch (err) {}
}

function cacheGetBig(cache, key) {
  try {
    const n = Number(cache.get(key + "_n"));
    if (!n) return null;
    const keys = [];
    for (let i = 0; i < n; i++) keys.push(key + "_" + i);
    const parts = cache.getAll(keys);
    let out = "";
    for (let i = 0; i < n; i++) {
      const p = parts[key + "_" + i];
      if (p === undefined || p === null) return null;
      out += p;
    }
    return out;
  } catch (err) {
    return null;
  }
}

function imageCacheKey(fileName) {
  return "img_" + fileName;
}

// getAll / removeAll accept max 100 keys per call
function cacheGetAllSafe(cache, keys) {
  const result = {};
  for (let i = 0; i < keys.length; i += 100) {
    const got = cache.getAll(keys.slice(i, i + 100));
    for (const k in got) result[k] = got[k];
  }
  return result;
}

function forgetImageIds(fileNames) {
  try {
    const cache = CacheService.getScriptCache();
    const keys = fileNames.map(imageCacheKey);
    for (let i = 0; i < keys.length; i += 100) cache.removeAll(keys.slice(i, i + 100));
  } catch (err) {}
}

// =====================================================================
// FAST SHEET READING
// Reads ONLY the rows that belong to one customer instead of the whole sheet.
// keyColIdx = 0-based column number that holds the customer id.
// =====================================================================
function getRowsByColumnValue(sheet, keyColIdx, value) {
  const lastRow = sheet.getLastRow();
  const lastCol = sheet.getLastColumn();
  if (lastRow < 2 || lastCol < 1 || keyColIdx >= lastCol) return [];

  // Read just the id column (small and quick)
  const keys = sheet.getRange(2, keyColIdx + 1, lastRow - 1, 1).getValues();
  const target = String(value);
  const matches = [];
  for (let i = 0; i < keys.length; i++) {
    if (String(keys[i][0]) === target) matches.push(i + 2);
  }
  if (matches.length === 0) return [];

  // Group neighbouring rows into blocks
  const runs = [];
  let runStart = matches[0], runPrev = matches[0];
  for (let i = 1; i < matches.length; i++) {
    if (matches[i] === runPrev + 1) {
      runPrev = matches[i];
    } else {
      runs.push([runStart, runPrev]);
      runStart = matches[i];
      runPrev = matches[i];
    }
  }
  runs.push([runStart, runPrev]);

  const out = [];
  if (runs.length <= 3) {
    // Few blocks: read each block directly
    for (let r = 0; r < runs.length; r++) {
      const block = sheet.getRange(runs[r][0], 1, runs[r][1] - runs[r][0] + 1, lastCol).getValues();
      for (let b = 0; b < block.length; b++) out.push(block[b]);
    }
  } else {
    // Many scattered rows: one single read from first to last match, then filter
    const first = matches[0], last = matches[matches.length - 1];
    const block = sheet.getRange(first, 1, last - first + 1, lastCol).getValues();
    const wanted = {};
    for (let i = 0; i < matches.length; i++) wanted[matches[i]] = true;
    for (let i = 0; i < block.length; i++) {
      if (wanted[first + i]) out.push(block[i]);
    }
  }
  return out;
}

// =====================================================================
// FAST IMAGE LINKS
// 1) file name -> file id is remembered in cache
// 2) names not remembered are found with ONE Drive search (not one search per image)
// =====================================================================
function escapeDriveQuery(text) {
  return String(text).replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

function lookupDriveFileIds(names) {
  const found = {};
  if (names.length === 0) return found;
  const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
  for (let i = 0; i < names.length; i += 15) {
    const chunk = names.slice(i, i + 15);
    try {
      const q = "trashed = false and (" +
      chunk.map(function (n) { return "title = '" + escapeDriveQuery(n) + "'"; }).join(" or ") + ")";
      const it = folder.searchFiles(q);
      while (it.hasNext()) {
        const f = it.next();
        const n = f.getName();
        if (!found[n]) found[n] = f.getId();
      }
    } catch (err) {
      // Fallback: the old, slower one-by-one way
      for (let c = 0; c < chunk.length; c++) {
        const it2 = folder.getFilesByName(chunk[c]);
        if (it2.hasNext()) found[chunk[c]] = it2.next().getId();
      }
    }
  }
  return found;
}

function driveUrlFromId(id) {
  return "https://lh3.googleusercontent.com/d/" + id + (IMAGE_WIDTH > 0 ? "=w" + IMAGE_WIDTH : "");
}

function convertAndroidPathsToDriveUrls(pathsString) {
  if (!pathsString || String(pathsString).trim() === "") return "";
  try {
    const items = String(pathsString).split(",").map(function (s) { return s.trim(); }).filter(Boolean);

    // Which items are real image file names that need a Drive id?
    const names = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.startsWith("<receipt>") && item.endsWith("</receipt>")) continue;
      if (item.startsWith("http://") || item.startsWith("https://")) continue;
        const name = item.split("/").pop();
      if (names.indexOf(name) === -1) names.push(name);
    }

    // 1) ids already remembered
    const idByName = {};
    const missing = [];
    if (names.length > 0) {
      const cache = CacheService.getScriptCache();
      const cached = cacheGetAllSafe(cache, names.map(imageCacheKey));
      for (let i = 0; i < names.length; i++) {
        const id = cached[imageCacheKey(names[i])];
        if (id) idByName[names[i]] = id;
                          else missing.push(names[i]);
      }

      // 2) ids not remembered -> one quick Drive search, then remember them
      if (missing.length > 0) {
        const foundIds = lookupDriveFileIds(missing);
        const toRemember = {};
        for (const n in foundIds) {
          idByName[n] = foundIds[n];
          toRemember[imageCacheKey(n)] = foundIds[n];
        }
        try {
          const keys = Object.keys(toRemember);
          for (let i = 0; i < keys.length; i += 100) {
            const part = {};
            keys.slice(i, i + 100).forEach(function (k) { part[k] = toRemember[k]; });
            cache.putAll(part, IMAGE_ID_CACHE_SECONDS);
          }
        } catch (err) {}
      }
    }

    // 3) build the final list in the original order (same rules as before)
    const validUrls = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.startsWith("<receipt>") && item.endsWith("</receipt>")) { validUrls.push(item); continue; }
      if (item.startsWith("http://") || item.startsWith("https://")) { validUrls.push(item); continue; }
        const id = idByName[item.split("/").pop()];
        if (id) validUrls.push(driveUrlFromId(id));
    }
    return validUrls.join(",");
  } catch (err) {
    return pathsString;
  }
}

// ==========================================
// AUTOMATED 4-DAY ROLLING BACKUP SYSTEM
// ==========================================
function performDailyBackupIfNeeded() {
  // Use a lock so simultaneous requests don't create multiple backups for the same day
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return;

                          try {
                            const scriptProperties = PropertiesService.getScriptProperties();
                            const lastBackupDate = scriptProperties.getProperty("LAST_BACKUP_DATE");

                            // Format current date in IST Timezone
                            const todayStr = Utilities.formatDate(new Date(), "Asia/Kolkata", "yyyy-MM-dd");

                            // If we already backed up today, do nothing and exit
                            if (lastBackupDate === todayStr) {
                              return;
                            }

                            const ss = getSpreadsheet();
                            const originalFile = DriveApp.getFileById(SPREADSHEET_ID);
                            // Find the folder where the original sheet lives
                            const folder = originalFile.getParents().hasNext() ? originalFile.getParents().next() : DriveApp.getRootFolder();

                            // 1. Create a copy for today
                            const backupName = "Backup_" + todayStr + "_" + ss.getName();
                            originalFile.makeCopy(backupName, folder);

                            // 2. Clean up old backups (keep only the last 4 days)
                            const files = folder.getFiles();
                            const backupFiles = [];

                            while (files.hasNext()) {
                              const file = files.next();
                              const name = file.getName();
                              // Identify valid backup files for this specific sheet
                              if (name.startsWith("Backup_") && name.endsWith("_" + ss.getName())) {
                                const datePart = name.split("_")[1]; // Extract the YYYY-MM-DD part
                                backupFiles.push({ file: file, date: datePart });
                              }
                            }

                            // Sort newest to oldest
                            backupFiles.sort((a, b) => {
                              if (a.date < b.date) return 1;
                              if (a.date > b.date) return -1;
                              return 0;
                            });

                            // Trashing older files past the 4-day limit
                            const MAX_BACKUPS = 4;
                            for (let i = MAX_BACKUPS; i < backupFiles.length; i++) {
                              backupFiles[i].file.setTrashed(true);
                            }

                            // Update the system property to flag today's backup as complete
                            scriptProperties.setProperty("LAST_BACKUP_DATE", todayStr);

                          } catch (e) {
                            console.error("Backup failed: " + e.toString());
                          } finally {
                            lock.releaseLock();
                          }
}

// ==========================================
// CUSTOMER FEEDBACK (STAR RATING) -> "feedback" sheet, saved date & time wise
// bill.html calls:  ?action=feedback&phone=...&name=...&rating=1..5
// * ONE feedback per customer, kept forever on the server (same on every browser/device)
// * Every new feedback is a NEW row at the bottom (oldest -> newest)
// * The bill lookup (doGet) also returns the customer's saved feedback inside customer.feedback
// * The app can download the full list with the secret key: action "fetch_feedbacks"
// ==========================================
const FEEDBACK_HEADERS = ["Date & Time", "Customer Name", "Phone", "Rating (out of 5)", "Customer ID"];
const FEEDBACK_DATE_FORMAT = "dd-MM-yyyy hh:mm:ss a";

// Last 10 digits of a phone number (same matching rule the bill lookup uses)
function lastTenDigits(value) {
  let d = String(value === null || value === undefined ? "" : value).replace(/\D/g, "");
  if (d.length >= 10) d = d.slice(-10);
                          return d;
}

// Sheet date cell -> text such as "11-10-2026 09:47:12 PM" (the Indian time that was stored)
function feedbackDateText(ss, value) {
  if (value instanceof Date) return Utilities.formatDate(value, ss.getSpreadsheetTimeZone(), FEEDBACK_DATE_FORMAT);
                          return String(value === null || value === undefined ? "" : value);
}

// Creates the sheet if needed. An older sheet that still has a "Stars" column is cleaned up automatically.
function getOrCreateFeedbackSheet(ss) {
  let sheet = ss.getSheetByName(FEEDBACK_SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(FEEDBACK_SHEET_NAME);
                          if (sheet.getLastRow() === 0) {
                            sheet.getRange(1, 1, 1, FEEDBACK_HEADERS.length)
                            .setValues([FEEDBACK_HEADERS])
                            .setFontWeight("bold")
                            .setBackground("#e2e8f0");
                            sheet.setFrozenRows(1);
                            sheet.setColumnWidth(1, 180);
                            sheet.setColumnWidth(2, 180);
                            sheet.setColumnWidth(3, 120);
                            sheet.setColumnWidth(4, 130);
                            sheet.setColumnWidth(5, 120);
                          } else {
                            const head = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(h => String(h).trim());
                            const starsAt = head.indexOf("Stars");
                            if (starsAt >= 0) sheet.deleteColumn(starsAt + 1); // remove the old Stars column, other data stays
                          }
                          return sheet;
}

// Reads every saved feedback (oldest -> newest). Finds columns by their header names,
// so it works for both the old layout (with Stars) and the new one.
function getFeedbackRecords(ss) {
  const sheet = ss.getSheetByName(FEEDBACK_SHEET_NAME);
  if (!sheet || sheet.getLastRow() < 2) return [];
                          const data = sheet.getDataRange().getValues();
  const head = data[0].map(h => String(h).trim());
  const col = function (title, fallback) { const i = head.indexOf(title); return i >= 0 ? i : fallback; };
  const cDate = col("Date & Time", 0), cName = col("Customer Name", 1), cPhone = col("Phone", 2),
                          cRating = col("Rating (out of 5)", 3), cId = col("Customer ID", 4);
                          const out = [];
                          for (let i = 1; i < data.length; i++) {
                            const r = data[i];
                            const phone = String(r[cPhone] === null || r[cPhone] === undefined ? "" : r[cPhone]).trim();
                            const id = String(r[cId] === null || r[cId] === undefined ? "" : r[cId]).trim();
                            if (phone === "" && id === "") continue; // blank row
                          out.push({
                            customerId: id,
                            name: String(r[cName] === null || r[cName] === undefined ? "" : r[cName]),
                                   phone: phone,
                                   rating: Number(r[cRating]) || 0,
                                   date: feedbackDateText(ss, r[cDate])
                          });
                          }
                          return out;
}

// Finds the saved feedback of one customer (matched by phone OR by customer ID)
function findFeedbackFor(records, customerId, phone10) {
  const idText = String(customerId === null || customerId === undefined ? "" : customerId).trim();
  for (let i = 0; i < records.length; i++) {
    const samePhone = phone10 !== "" && lastTenDigits(records[i].phone) === phone10;
    const sameId = idText !== "" && records[i].customerId === idText;
    if (samePhone || sameId) return records[i];
  }
  return null;
}

// Used by the bill lookup: {rating, date} if this customer already gave feedback, otherwise null.
// Never throws - a problem here must never break the bill page.
function getCustomerFeedback(ss, customerId, phone) {
  try {
    const found = findFeedbackFor(getFeedbackRecords(ss), customerId, lastTenDigits(phone));
    return found ? { rating: found.rating, date: found.date } : null;
  } catch (err) {
    return null;
  }
}

function handleFeedback(e) {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    const p = e.parameter || {};

    // 1) Validate the rating (must be a whole number 1-5)
    const rating = Number(p.rating);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      return responseJSON({ status: "error", message: "Invalid rating." });
    }

    // 2) The phone must belong to a real customer (blocks random/fake submissions)
    const phone10 = lastTenDigits(p.phone);
    if (!phone10) return responseJSON({ status: "error", message: "Phone required." });

                          const ss = getSpreadsheet();
                          const custSheet = ss.getSheetByName("customers");
                          if (!custSheet) return responseJSON({ status: "error", message: "'customers' missing." });

                          // Only the phone column is read (faster than the whole sheet)
                          const custLastRow = custSheet.getLastRow();
                          let customer = null;
                          if (custLastRow >= 2) {
                            const phones = custSheet.getRange(2, 3, custLastRow - 1, 1).getValues();
                            for (let i = 0; i < phones.length; i++) {
                              if (lastTenDigits(phones[i][0]) === phone10) {
                                const row = custSheet.getRange(i + 2, 1, 1, 3).getValues()[0];
                                customer = { id: row[0], name: row[1], phone: row[2] };
                                break;
                              }
                            }
                          }
                          if (!customer) return responseJSON({ status: "not_found", message: "Customer not found." });

                          // Name comes from your customers sheet (trusted); falls back to the name the page sent
                          const name = String(customer.name || p.name || "").trim().substring(0, 100);

                          // 3) Current date & time in IST. Stored as a REAL date-time (sortable / filterable in Sheets)
                          //    and shown the same way even if the spreadsheet itself is set to another time zone.
                          const istNow = Utilities.formatDate(new Date(), "Asia/Kolkata", "yyyy-MM-dd HH:mm:ss");
                          const when = Utilities.parseDate(istNow, ss.getSpreadsheetTimeZone(), "yyyy-MM-dd HH:mm:ss");

                          // 4) Lock = two submissions at the same moment can never both get in or overwrite each other.
                          lock.waitLock(15000);
                          locked = true;
                          const sheet = getOrCreateFeedbackSheet(ss);

                          // ONE FEEDBACK PER CUSTOMER (by phone or ID). The first one is kept; the stored one is sent back
                          // so the page can show it, even when the customer opens the bill on a different browser/device.
                          const already = findFeedbackFor(getFeedbackRecords(ss), customer.id, phone10);
                          if (already) {
                            return responseJSON({
                              status: "already_submitted",
                              message: "Feedback already received.",
                              feedback: { rating: already.rating, date: already.date }
                            });
                          }

                          const row = sheet.getLastRow() + 1;
                          const range = sheet.getRange(row, 1, 1, FEEDBACK_HEADERS.length);
                          // "@" = plain text: keeps phone numbers intact and stops any name starting with = from becoming a formula
                          range.setNumberFormats([[FEEDBACK_DATE_FORMAT, "@", "@", "0", "@"]]);
                          range.setValues([[when, name, String(customer.phone).trim(), rating, String(customer.id)]]);

                          // The saved bills contain the feedback, so forget them (they rebuild on the next visit)
                          bumpCacheVersion();

                          return responseJSON({
                            status: "success",
                            message: "Feedback saved.",
                            feedback: { rating: rating, date: Utilities.formatDate(when, ss.getSpreadsheetTimeZone(), FEEDBACK_DATE_FORMAT) }
                          });
  } catch (error) {
    return responseJSON({ status: "error", message: "Feedback failed: " + error.toString() });
  } finally {
    if (locked) lock.releaseLock();
  }
}

// ==========================================
// APP MODULE: all feedback list (needs the SECRET API KEY)
//   POST (JSON body):  { "action": "fetch_feedbacks", "apiKey": "<SECRET_API_KEY>" }
//   GET  (for testing): ?action=fetch_feedbacks&apiKey=<SECRET_API_KEY>
// Returns newest feedback first, plus total count, average and how many 1-5 star ratings.
// ==========================================
function fetchAllFeedbacks() {
  try {
    const ss = getSpreadsheet();
    const records = getFeedbackRecords(ss);

    const distribution = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
    let counted = 0, total = 0;
    for (let i = 0; i < records.length; i++) {
      const r = records[i].rating;
      if (r >= 1 && r <= 5) { distribution[String(r)]++; counted++; total += r; }
    }

    const feedbacks = records.slice().reverse().map(function (r) {
      return { customerId: r.customerId, name: r.name, phone: r.phone, rating: r.rating, date: r.date };
    });

    return responseJSON({
      status: "success",
      count: records.length,
      average: counted ? Math.round((total / counted) * 10) / 10 : 0,
                        distribution: distribution,
                        feedbacks: feedbacks
    });
  } catch (error) {
    return responseJSON({ status: "error", message: "Fetch feedbacks failed: " + error.toString() });
  }
}

// ==========================================
// doGet  -  THE BILL LOOKUP (this is the part that was slow)
// ==========================================
function doGet(e) {
  try {
    const params = (e && e.parameter) ? e.parameter : {};

    // Tiny request for a "keep warm" ping (see notes) - does no work at all
    if (params.action === "ping") return responseJSON({ status: "ok" });

                          // Feedback requests are handled first (they carry no apiKey, so they must not reach the checks below)
                          if (params.action === "feedback") return handleFeedback(e);
                          // App: full feedback list (secret key required)
                          if (params.action === "fetch_feedbacks") {
                            if (params.apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Invalid API Key." });
                          return fetchAllFeedbacks();
                          }

                          const phone = params.phone || null;
                          const bill = params.bill || null;
                          const apiKey = params.apiKey || null;

                          if (!phone && !bill) return responseJSON({ status: "error", message: "Phone or Bill required." });
                          if (phone && apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Invalid API Key." });

                          // ---------- FAST PATH: customer bill already prepared -> send it instantly ----------
                          // Only the public bill page (?bill=...) uses the cache. The app (?phone=...&apiKey=...) always gets fresh data.
                          const cache = CacheService.getScriptCache();
                          let cacheKey = null;
                          if (bill && !phone) {
                            const bill10 = lastTenDigits(bill);
                            if (bill10 !== "") {
                              cacheKey = "bill_" + getCacheVersion() + "_" + bill10;
                              const hit = cacheGetBig(cache, cacheKey);
                              if (hit) return ContentService.createTextOutput(hit).setMimeType(ContentService.MimeType.JSON);
                            }
                          }

                          // ---------- SLOW PATH (first visit / after a change) ----------
                          const ss = getSpreadsheet();
                          const custSheet = ss.getSheetByName("customers");
                          if (!custSheet) return responseJSON({ status: "error", message: "'customers' missing." });

                          // 1) Find the customer by reading ONLY the phone column
                          const custLastRow = custSheet.getLastRow();
                          let customerRowNumber = 0;
                          if (custLastRow >= 2) {
                            const phones = custSheet.getRange(2, 3, custLastRow - 1, 1).getValues();
                            if (bill) {
                              const cleanBill = lastTenDigits(bill);
                              if (cleanBill !== "") {
                                for (let i = 0; i < phones.length; i++) {
                                  if (lastTenDigits(phones[i][0]) === cleanBill) { customerRowNumber = i + 2; break; }
                                }
                              }
                            } else {
                              const wanted = String(phone).trim();
                              for (let i = 0; i < phones.length; i++) {
                                if (String(phones[i][0]).trim() === wanted) { customerRowNumber = i + 2; break; }
                              }
                            }
                          }
                          if (!customerRowNumber) return responseJSON({ status: "not_found", message: "Not found." });

                          // 2) Read just that one customer row
                          const colsToRead = Math.min(8, custSheet.getMaxColumns());
                          const row = custSheet.getRange(customerRowNumber, 1, 1, colsToRead).getValues()[0];
                          const customerId = row[0];
                          const customer = {
                            id: customerId,
                            name: row[1],
                            phone: row[2],
                            address: row[3],
                            due: row[4],
                            images: convertAndroidPathsToDriveUrls(row[5]),
                          createdAt: row[6],
                          dueHistory: row[7]
                          };

                          // Feedback this customer already gave (null if none) - so the bill page shows it on every browser/device
                          customer.feedback = getCustomerFeedback(ss, customerId, customer.phone);

                          // 3) Transactions - only this customer's rows
                          const transactions = [];
                          const transSheet = ss.getSheetByName("transactions");
                          if (transSheet) {
                            const rows = getRowsByColumnValue(transSheet, 1, customerId);
                            for (let i = 0; i < rows.length; i++) {
                              transactions.push({ id: rows[i][0], amount: rows[i][2], date: rows[i][3], note: rows[i][4] });
                            }
                          }

                          // 4) Receipt calculations - only this customer's rows (these hold big JSON, so this saves the most time)
                          const receiptCalculations = [];
                          const receiptSheet = ss.getSheetByName("receipt_calculations");
                          if (receiptSheet && receiptSheet.getLastRow() > 0 && receiptSheet.getLastColumn() > 0) {
                            const headers = receiptSheet.getRange(1, 1, 1, receiptSheet.getLastColumn()).getValues()[0];

                            const idIdx = headers.indexOf("id") !== -1 ? headers.indexOf("id") : 0;
                            const custIdIdx = headers.indexOf("customerId") !== -1 ? headers.indexOf("customerId") :
                            (headers.indexOf("customer_id") !== -1 ? headers.indexOf("customer_id") : 1);
                            const jsonIdx = headers.indexOf("calculationJson") !== -1 ? headers.indexOf("calculationJson") : 2;
                            const dateIdx = headers.indexOf("datetime") !== -1 ? headers.indexOf("datetime") : 3;

                            const rows = getRowsByColumnValue(receiptSheet, custIdIdx, customerId);
                            for (let i = 0; i < rows.length; i++) {
                              const jsonString = rows[i][jsonIdx];
                              let skip = false;

                              // Only parse the JSON when it could be a draft (saves a lot of time on big receipts)
                              if (jsonString && typeof jsonString === "string" && jsonString.indexOf("draft") !== -1) {
                                try {
                                  const parsedJson = JSON.parse(jsonString);
                                  if (parsedJson && parsedJson.type === "draft") skip = true;
                                } catch (err) {
                                  // Ignore parse errors, keep the data to be safe
                                }
                              }

                              if (!skip) {
                                receiptCalculations.push({
                                  id: rows[i][idIdx],
                                  calculationJson: jsonString,
                                  datetime: rows[i][dateIdx]
                                });
                              }
                            }
                          }

                          // 5) Messages - only this customer's rows
                          const messages = [];
                          const msgSheet = ss.getSheetByName("messages");
                          if (msgSheet) {
                            const rows = getRowsByColumnValue(msgSheet, 1, customerId);
                            for (let i = 0; i < rows.length; i++) {
                              messages.push({ id: rows[i][0], text: rows[i][2], date: rows[i][3] });
                            }
                          }

                          // 6) Build the answer, save it for the next visit, send it
                          const json = JSON.stringify({
                            status: "success",
                            data: { customer: customer, transactions: transactions, receipt_calculations: receiptCalculations, messages: messages }
                          });
                          if (cacheKey) cachePutBig(cache, cacheKey, json, BILL_CACHE_SECONDS);

                          return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return responseJSON({ status: "error", message: error.toString() });
  }
}

// ==========================================
// doPost  -  used by your app
// ==========================================
const READ_ONLY_ACTIONS = ["fetch_full_database", "fetch_feedbacks"];

function doPost(e) {
  let action = null;
  try {
    if (!e.postData || !e.postData.contents) return responseJSON({ status: "error", message: "No payload." });
                          const parsedData = JSON.parse(e.postData.contents);

                          // Check API Key first before proceeding
                          if (parsedData.apiKey !== SECRET_API_KEY) return responseJSON({ status: "error", message: "Unauthorized action. Invalid API Key." });

                          action = parsedData.action;

                          // Trigger daily backup before modifying anything
                          performDailyBackupIfNeeded();

                          switch (action) {
                            case "full_text_backup": return handleFullTextBackup(parsedData);
                            case "upload_image": return uploadImage(parsedData);
                            case "delete_images": return deleteImages(parsedData);
                            case "add_customer": return saveCustomerAndMessage(parsedData);
                            case "add_expense": return addExpense(parsedData);
                            case "delete_expense": return deleteExpense(parsedData);
                            case "add_order": return addOrder(parsedData);
                            case "add_bulk_orders": return addBulkOrders(parsedData);
                            case "delete_orders_bulk": return delete_orders_bulk(parsedData);
                            case "delete_order": return deleteOrder(parsedData);
                            case "add_temp_customer": return addTempCustomer(parsedData);
                            case "delete_temp_customer": return deleteTempCustomer(parsedData);
                            case "fetch_full_database": return fetchFullDatabase();
                            case "fetch_feedbacks": return fetchAllFeedbacks();
                            default: return responseJSON({ status: "error", message: "Unknown action trigger" });
                          }
  } catch (error) {
    return responseJSON({ status: "error", message: error.toString() });
  } finally {
    // Anything the app changed -> forget the saved customer bills so users never see old data
    if (action && READ_ONLY_ACTIONS.indexOf(action) === -1) bumpCacheVersion();
  }
}

function handleFullTextBackup(data) {
  try {
    const ss = getSpreadsheet();
    const db = data.database;
    const activeImages = data.active_images || [];

    if (db && typeof db === "object") {
      for (let tableName in db) {
        if (!db.hasOwnProperty(tableName)) continue;
                          let rows = db[tableName];
        let sheet = ss.getSheetByName(tableName) || ss.insertSheet(tableName);

        if (Array.isArray(rows) && rows.length > 0) {
          // We have data: Clear the sheet and rewrite headers + data
          sheet.clear();

          let headers = Object.keys(rows[0]);
          let matrix = [headers];
          for (let i = 0; i < rows.length; i++) {
            matrix.push(headers.map(h => {
              let val = rows[i][h];
              return (typeof val === "object" && val !== null) ? JSON.stringify(val) : (val === null || val === undefined ? "" : val);
            }));
          }
          sheet.getRange(1, 1, matrix.length, headers.length).setValues(matrix);
        } else {
          // Table is empty: Keep headers in row 1, but clear all old data from row 2 downwards
          let lastRow = sheet.getLastRow();
          let lastCol = sheet.getLastColumn();
          if (lastRow > 1 && lastCol > 0) {
            sheet.getRange(2, 1, lastRow - 1, lastCol).clearContent();
          }
        }
      }
    }

    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
    const driveFiles = folder.getFiles();
    const driveFileNames = new Set();
    const activeImageSet = new Set(activeImages);
    const trashedNames = [];
    let trashedCount = 0;

    while (driveFiles.hasNext()) {
      let file = driveFiles.next();
      let fileName = file.getName();

      if (activeImageSet.has(fileName)) {
        driveFileNames.add(fileName);
      } else {
        file.setTrashed(true);
        trashedNames.push(fileName);
        trashedCount++;
      }
    }

    // Trashed images must not stay in the remembered "name -> id" list
    forgetImageIds(trashedNames);

                          const missingImages = [];
    for (let i = 0; i < activeImages.length; i++) {
      if (!driveFileNames.has(activeImages[i])) {
        missingImages.push(activeImages[i]);
      }
    }

    return responseJSON({
      status: "success",
      message: "Database synced.",
      trashed_count: trashedCount,
      missing_images: missingImages
    });
  } catch (error) {
    return responseJSON({ status: "error", message: "Full backup failed: " + error.toString() });
  }
}

function uploadImage(data) {
  try {
    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
    const contentType = data.mimeType || "image/jpeg";
    const fileName = data.filename || "image.jpg";

    // Clean base64 string to ensure valid decoding
    let base64Str = data.base64 || "";
    if (base64Str.indexOf(",") !== -1) {
      base64Str = base64Str.split(",")[1];
    }

    const bytes = Utilities.base64Decode(base64Str);
    const blob = Utilities.newBlob(bytes, contentType, fileName);

    // Trash old file with same name to prevent duplicates
    const existingFiles = folder.getFilesByName(fileName);
    while (existingFiles.hasNext()) {
      existingFiles.next().setTrashed(true);
    }

    // Safely generate the file from the binary blob
    const file = folder.createFile(blob);
    try {
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (e) {}

    // Remember the new file id right away, so the first bill view needs no Drive search
    try {
      CacheService.getScriptCache().put(imageCacheKey(fileName), file.getId(), IMAGE_ID_CACHE_SECONDS);
    } catch (e) {}

    return responseJSON({ status: "success", fileId: file.getId() });
  } catch (error) {
    return responseJSON({ status: "error", message: "Upload failed: " + error.toString() });
  }
}

function fetchFullDatabase() {
  try {
    const ss = getSpreadsheet();
    const sheets = ss.getSheets();
    const db = {};

    for (let i = 0; i < sheets.length; i++) {
      let sheetName = sheets[i].getName();
      if (sheetName === FEEDBACK_SHEET_NAME) continue; // feedback log is not part of the app database
                          let data = sheets[i].getDataRange().getValues();
      if (data.length < 2) continue; // Skip empty sheets

                          let headers = data[0];
      let rows = [];
      for (let j = 1; j < data.length; j++) {
        let obj = {};
        for (let k = 0; k < headers.length; k++) {
          obj[headers[k]] = data[j][k];
        }
        rows.push(obj);
      }
      db[sheetName] = rows;
    }
    return responseJSON({ status: "success", database: db });
  } catch (error) {
    return responseJSON({ status: "error", message: error.toString() });
  }
}

// -----------------------------------------------------
// Placeholder functions as requested (to be filled later)
// -----------------------------------------------------
function deleteImages(data) {}
function saveCustomerAndMessage(data) {}
function addExpense(data) {}
function deleteExpense(data) {}
function addOrder(data) {}
function addBulkOrders(data) {}
function delete_orders_bulk(data) {}
function deleteOrder(data) {}
function addTempCustomer(data) {}
function deleteTempCustomer(data) {}
