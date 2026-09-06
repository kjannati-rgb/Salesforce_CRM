// Generates one CustomMetadata record file per country, mapping the real Account.BillingCountry
// value (exact strings pulled from FULLUAT via SOQL GROUP BY on Office-record-type Accounts) to a
// macro region bucket (EMEA / North America / APAC / LATAM). Run: node scripts/adhoc/generate_country_region_mdt.js
const fs = require('fs');
const path = require('path');

// [BillingCountry exact string, Region]
const ROWS = [
  ['Afghanistan', 'APAC'],
  ['Aland Islands', 'EMEA'],
  ['Albania', 'EMEA'],
  ['Algeria', 'Middle East & Africa'],
  ['American Samoa', 'APAC'],
  ['Andorra', 'EMEA'],
  ['Angola', 'Middle East & Africa'],
  ['Anguilla', 'LATAM'],
  ['Antarctica', 'EMEA'],
  ['Antigua and Barbuda', 'LATAM'],
  ['Argentina', 'LATAM'],
  ['Armenia', 'EMEA'],
  ['Aruba', 'LATAM'],
  ['Australia', 'APAC'],
  ['Austria', 'EMEA'],
  ['Azerbaijan', 'EMEA'],
  ['Bahamas', 'LATAM'],
  ['Bahrain', 'Middle East & Africa'],
  ['Bangladesh', 'APAC'],
  ['Barbados', 'LATAM'],
  ['Belarus', 'EMEA'],
  ['Belgium', 'EMEA'],
  ['Belize', 'LATAM'],
  ['Benin', 'Middle East & Africa'],
  ['Bermuda', 'North America'],
  ['Bhutan', 'APAC'],
  ['Bolivia, Plurinational State of', 'LATAM'],
  ['Bonaire, Sint Eustatius and Saba', 'LATAM'],
  ['Bosnia and Herzegovina', 'EMEA'],
  ['Botswana', 'Middle East & Africa'],
  ['Brazil', 'LATAM'],
  ['British Indian Ocean Territory', 'APAC'],
  ['Brunei Darussalam', 'APAC'],
  ['Bulgaria', 'EMEA'],
  ['Burkina Faso', 'Middle East & Africa'],
  ['Burundi', 'Middle East & Africa'],
  ['Cambodia', 'APAC'],
  ['Cameroon', 'Middle East & Africa'],
  ['Canada', 'North America'],
  ['Cape Verde', 'Middle East & Africa'],
  ['Cayman Islands', 'LATAM'],
  ['Central African Republic', 'Middle East & Africa'],
  ['Chad', 'Middle East & Africa'],
  ['Chile', 'LATAM'],
  ['China', 'APAC'],
  ['Chinese Taipei', 'APAC'],
  ['Cocos (Keeling) Islands', 'APAC'],
  ['Colombia', 'LATAM'],
  ['Comoros', 'Middle East & Africa'],
  ['Congo', 'Middle East & Africa'],
  ['Congo, the Democratic Republic of the', 'Middle East & Africa'],
  ['Cook Islands', 'APAC'],
  ['Costa Rica', 'LATAM'],
  ["Cote d'Ivoire", 'Middle East & Africa'],
  ['Croatia', 'EMEA'],
  ['Cuba', 'LATAM'],
  ['Curaçao', 'LATAM'],
  ['Cyprus', 'EMEA'],
  ['Czech Republic', 'EMEA'],
  ['Denmark', 'EMEA'],
  ['Djibouti', 'Middle East & Africa'],
  ['Dominica', 'LATAM'],
  ['Dominican Republic', 'LATAM'],
  ['Ecuador', 'LATAM'],
  ['Egypt', 'Middle East & Africa'],
  ['El Salvador', 'LATAM'],
  ['Equatorial Guinea', 'Middle East & Africa'],
  ['Eritrea', 'Middle East & Africa'],
  ['Estonia', 'EMEA'],
  ['Ethiopia', 'Middle East & Africa'],
  ['Falkland Islands (Malvinas)', 'LATAM'],
  ['Faroe Islands', 'EMEA'],
  ['Fiji', 'APAC'],
  ['Finland', 'EMEA'],
  ['France', 'EMEA'],
  ['French Guiana', 'LATAM'],
  ['French Polynesia', 'APAC'],
  ['Gabon', 'Middle East & Africa'],
  ['Gambia', 'Middle East & Africa'],
  ['Georgia', 'EMEA'],
  ['Germany', 'EMEA'],
  ['Ghana', 'Middle East & Africa'],
  ['Gibraltar', 'EMEA'],
  ['Greece', 'EMEA'],
  ['Greenland', 'North America'],
  ['Grenada', 'LATAM'],
  ['Guadeloupe', 'LATAM'],
  ['Guam', 'APAC'],
  ['Guatemala', 'LATAM'],
  ['Guernsey', 'EMEA'],
  ['Guinea', 'Middle East & Africa'],
  ['Guinea-Bissau', 'Middle East & Africa'],
  ['Guyana', 'LATAM'],
  ['Haiti', 'LATAM'],
  ['Honduras', 'LATAM'],
  ['Hong Kong', 'APAC'],
  ['Hungary', 'EMEA'],
  ['Iceland', 'EMEA'],
  ['India', 'APAC'],
  ['Indonesia', 'APAC'],
  ['Iran, Islamic Republic of', 'Middle East & Africa'],
  ['Iraq', 'Middle East & Africa'],
  ['Ireland', 'EMEA'],
  ['Isle of Man', 'EMEA'],
  ['Israel', 'Middle East & Africa'],
  ['Italy', 'EMEA'],
  ['Jamaica', 'LATAM'],
  ['Japan', 'APAC'],
  ['Jersey', 'EMEA'],
  ['Jordan', 'Middle East & Africa'],
  ['Kazakhstan', 'EMEA'],
  ['Kenya', 'Middle East & Africa'],
  ["Korea, Democratic People's Republic of", 'APAC'],
  ['Korea, Republic of', 'APAC'],
  ['Kuwait', 'Middle East & Africa'],
  ['Kyrgyzstan', 'EMEA'],
  ["Lao People's Democratic Republic", 'APAC'],
  ['Latvia', 'EMEA'],
  ['Lebanon', 'Middle East & Africa'],
  ['Lesotho', 'Middle East & Africa'],
  ['Liberia', 'Middle East & Africa'],
  ['Libyan Arab Jamahiriya', 'Middle East & Africa'],
  ['Liechtenstein', 'EMEA'],
  ['Lithuania', 'EMEA'],
  ['Luxembourg', 'EMEA'],
  ['Macao', 'APAC'],
  ['Macedonia, the former Yugoslav Republic of', 'EMEA'],
  ['Madagascar', 'Middle East & Africa'],
  ['Malawi', 'Middle East & Africa'],
  ['Malaysia', 'APAC'],
  ['Maldives', 'APAC'],
  ['Mali', 'Middle East & Africa'],
  ['Malta', 'EMEA'],
  ['Marshall Islands', 'APAC'],
  ['Martinique', 'LATAM'],
  ['Mauritania', 'Middle East & Africa'],
  ['Mauritius', 'Middle East & Africa'],
  ['Mexico', 'LATAM'],
  ['Micronesia', 'APAC'],
  ['Moldova, Republic of', 'EMEA'],
  ['Monaco', 'EMEA'],
  ['Mongolia', 'APAC'],
  ['Montenegro', 'EMEA'],
  ['Montserrat', 'LATAM'],
  ['Morocco', 'Middle East & Africa'],
  ['Mozambique', 'Middle East & Africa'],
  ['Myanmar', 'APAC'],
  ['Namibia', 'Middle East & Africa'],
  ['Nauru', 'APAC'],
  ['Nepal', 'APAC'],
  ['Netherlands', 'EMEA'],
  ['New Caledonia', 'APAC'],
  ['New Zealand', 'APAC'],
  ['Nicaragua', 'LATAM'],
  ['Niger', 'Middle East & Africa'],
  ['Nigeria', 'Middle East & Africa'],
  ['Norfolk Island', 'APAC'],
  ['Northern Mariana Islands', 'APAC'],
  ['Norway', 'EMEA'],
  ['Oman', 'Middle East & Africa'],
  ['Pakistan', 'APAC'],
  ['Palau', 'APAC'],
  ['Palestinian Territory, Occupied', 'Middle East & Africa'],
  ['Panama', 'LATAM'],
  ['Papua New Guinea', 'APAC'],
  ['Paraguay', 'LATAM'],
  ['Peru', 'LATAM'],
  ['Philippines', 'APAC'],
  ['Pitcairn', 'APAC'],
  ['Poland', 'EMEA'],
  ['Portugal', 'EMEA'],
  ['Qatar', 'Middle East & Africa'],
  ['Republic of Kosovo', 'EMEA'],
  ['Reunion', 'Middle East & Africa'],
  ['Romania', 'EMEA'],
  ['Russian Federation', 'EMEA'],
  ['Rwanda', 'Middle East & Africa'],
  ['Saint Barthélemy', 'LATAM'],
  ['Saint Kitts and Nevis', 'LATAM'],
  ['Saint Lucia', 'LATAM'],
  ['Saint Vincent and the Grenadines', 'LATAM'],
  ['Samoa', 'APAC'],
  ['San Marino', 'EMEA'],
  ['Sao Tome and Principe', 'Middle East & Africa'],
  ['Saudi Arabia', 'Middle East & Africa'],
  ['Senegal', 'Middle East & Africa'],
  ['Serbia', 'EMEA'],
  ['Seychelles', 'Middle East & Africa'],
  ['Sierra Leone', 'Middle East & Africa'],
  ['Singapore', 'APAC'],
  ['Sint Maarten (Dutch part)', 'LATAM'],
  ['Slovakia', 'EMEA'],
  ['Slovenia', 'EMEA'],
  ['Solomon Islands', 'APAC'],
  ['Somalia', 'Middle East & Africa'],
  ['South Africa', 'Middle East & Africa'],
  ['South Sudan', 'Middle East & Africa'],
  ['Spain', 'EMEA'],
  ['Sri Lanka', 'APAC'],
  ['Sudan', 'Middle East & Africa'],
  ['Suriname', 'LATAM'],
  ['Swaziland', 'Middle East & Africa'],
  ['Sweden', 'EMEA'],
  ['Switzerland', 'EMEA'],
  ['Syrian Arab Republic', 'Middle East & Africa'],
  ['Taiwan', 'APAC'],
  ['Tajikistan', 'EMEA'],
  ['Tanzania, United Republic of', 'Middle East & Africa'],
  ['Thailand', 'APAC'],
  ['Timor-Leste', 'APAC'],
  ['Togo', 'Middle East & Africa'],
  ['Tonga', 'APAC'],
  ['Trinidad and Tobago', 'LATAM'],
  ['Tunisia', 'Middle East & Africa'],
  ['Turkey', 'Middle East & Africa'],
  ['Turkmenistan', 'EMEA'],
  ['Turks and Caicos Islands', 'LATAM'],
  ['Uganda', 'Middle East & Africa'],
  ['Ukraine', 'EMEA'],
  ['United Arab Emirates', 'Middle East & Africa'],
  ['United Kingdom', 'EMEA'],
  ['United States', 'North America'],
  ['United States Minor Outlying Islands', 'North America'],
  ['Uruguay', 'LATAM'],
  ['Uzbekistan', 'EMEA'],
  ['Vanuatu', 'APAC'],
  ['Venezuela, Bolivarian Republic of', 'LATAM'],
  ['Viet Nam', 'APAC'],
  ['Virgin Islands, British', 'LATAM'],
  ['Virgin Islands, US', 'LATAM'],
  ['Yemen', 'Middle East & Africa'],
  ['Zambia', 'Middle East & Africa'],
  ['Zimbabwe', 'Middle East & Africa']
];

function developerName(country) {
  // Any non-alphanumeric character (spaces, commas, apostrophes, accents, parens) becomes an
  // underscore — simplest reliable way to get a legal Salesforce DeveloperName from arbitrary text.
  let s = country
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/_{2,}/g, '_');
  if (/^[0-9]/.test(s)) s = 'C_' + s;
  return s.substring(0, 38); // leave room for uniqueness collisions to still be legal
}

const outDir = path.join(__dirname, '..', '..', 'force-app', 'main', 'default', 'customMetadata');
const seen = new Map();
let written = 0;

// MasterLabel is capped at 40 chars; a handful of ISO country names exceed that. Country__c (the
// actual match value) always keeps the full original name — only the display label is shortened.
const LABEL_OVERRIDES = {
  'Macedonia, the former Yugoslav Republic of': 'North Macedonia'
};

for (const [country, region] of ROWS) {
  let dev = developerName(country);
  if (seen.has(dev)) {
    dev = dev.substring(0, 35) + '_' + (seen.get(dev) + 1);
    seen.set(developerName(country), seen.get(developerName(country)) + 1);
  } else {
    seen.set(dev, 1);
  }
  const fullName = `Country_Region.${dev}`;
  const label = LABEL_OVERRIDES[country] || country;
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" fields="Country__c,Region__c">
    <label>${escapeXml(label)}</label>
    <protected>false</protected>
    <values>
        <field>Country__c</field>
        <value xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">${escapeXml(country)}</value>
    </values>
    <values>
        <field>Region__c</field>
        <value xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">${escapeXml(region)}</value>
    </values>
</CustomMetadata>
`;
  fs.writeFileSync(path.join(outDir, `${fullName}.md-meta.xml`), xml);
  written++;
}

function escapeXml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

console.log(`Wrote ${written} Country_Region__mdt records to ${outDir}`);
console.log(`Distinct DeveloperNames: ${seen.size}`);
