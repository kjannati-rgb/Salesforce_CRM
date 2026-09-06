// One-time reclassification: pulls the Middle East + Africa countries currently bucketed under
// EMEA in generate_country_region_mdt.js's ROWS array out into their own 'Middle East & Africa'
// region, then regenerates the 233 CMDT record files from the updated ROWS.
// Run: node scripts/adhoc/reclassify_mea.js
const fs = require('fs');
const path = require('path');

const MEA_COUNTRIES = new Set([
  // Middle East (15)
  'Bahrain', 'Iran, Islamic Republic of', 'Iraq', 'Israel', 'Jordan', 'Kuwait', 'Lebanon', 'Oman',
  'Palestinian Territory, Occupied', 'Qatar', 'Saudi Arabia', 'Syrian Arab Republic', 'Turkey',
  'United Arab Emirates', 'Yemen',
  // Africa (55)
  'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi', 'Cameroon', 'Cape Verde',
  'Central African Republic', 'Chad', 'Comoros', 'Congo', 'Congo, the Democratic Republic of the',
  "Cote d'Ivoire", 'Djibouti', 'Egypt', 'Equatorial Guinea', 'Eritrea', 'Ethiopia', 'Gabon',
  'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau', 'Kenya', 'Lesotho', 'Liberia',
  'Libyan Arab Jamahiriya', 'Madagascar', 'Malawi', 'Mali', 'Mauritania', 'Mauritius', 'Morocco',
  'Mozambique', 'Namibia', 'Niger', 'Nigeria', 'Reunion', 'Rwanda', 'Sao Tome and Principe',
  'Senegal', 'Seychelles', 'Sierra Leone', 'Somalia', 'South Africa', 'South Sudan', 'Sudan',
  'Swaziland', 'Tanzania, United Republic of', 'Togo', 'Tunisia', 'Uganda', 'Zambia', 'Zimbabwe'
]);

const genPath = path.join(__dirname, 'generate_country_region_mdt.js');
let src = fs.readFileSync(genPath, 'utf8');

let changed = 0;
for (const country of MEA_COUNTRIES) {
  // Match the exact ROWS line for this country with region 'EMEA' and flip it.
  const escaped = country.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(\\[(?:'${escaped}'|"${escaped}")\\s*,\\s*)'EMEA'(\\])`, 'g');
  const before = src;
  src = src.replace(re, `$1'Middle East & Africa'$2`);
  if (src !== before) changed++;
}

if (changed !== MEA_COUNTRIES.size) {
  console.error(`Expected to change ${MEA_COUNTRIES.size} rows, actually changed ${changed}. Aborting without writing.`);
  process.exit(1);
}

fs.writeFileSync(genPath, src);
console.log(`Reclassified ${changed} countries from EMEA to 'Middle East & Africa' in ${genPath}`);
