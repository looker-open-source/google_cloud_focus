<img width="1005" alt="unnamed (1)" src="https://github.com/looker-open-source/google_cloud_focus/assets/25227290/b5be0a4b-cc2f-43fa-bbdb-9e2b64c22c8e">

# Looker Template for FOCUS™ v1.0 GA
Google Cloud Unveils FOCUS: Streamlining Cloud Cost Management Across Providers with a Looker Explore and Dashboard


## FOCUS Cloud Billing Overview
Google Cloud's FOCUS BigQuery view seamlessly integrates with Looker, offering businesses a unified and streamlined approach to cloud cost management across providers.

## Key Points

- FOCUS Looker explore transforms Google Cloud billing data into FOCUS specification, enhancing compatibility.
- Enables querying and analyzing Google Cloud costs alongside other providers using common FOCUS format.
- Utilizes Detailed Billing Export and Price Exports, simplifying setup for users.
- Google Cloud's commitment to open standards enhances collaboration with customers, FinOps practitioners, and industry leaders.

## Data Exports Needed 
- Detailed Billing Export
- Pricing Export

## Steps to Enable Looker Template
The LookML is written in BigQuery Standard SQL.
1. Prepare Your Looker Environment:
	- Ensure you have permissions to create a Looker project dedicated to this analysis.
	- Have the following information on hand:
		- The name of your database connection in Looker.
		- The date you want your analysis to start from.
		- The names of the pricing and billing tables within your database.

2. Download and Adapt the Repository:
	- Create a new LookML Project and select "Clone Public Git Repository" as your starting point. Copy the following git path: git://github.com/looker-open-source/google_cloud_focus.git
	- Locate the manifest file (named manifest.lkml) within the downloaded repository.
	- Open the manifest file and modify the following constants to match your specific environment:
		- connection: Replace with the name of your Looker database connection.
		- date: Replace with the date you wish to start your analysis from.
		- pricing_table: Replace with the name of your pricing table.
		- billing_table: Replace with the name of your detailed billing table.
3. Test Your Configuration:
	- Navigate to the "Focus" Explore in Looker and verify that the data is loading correctly and as expected.
4. Deploy to Production:
	- Commit your modified LookML files.
	- Deploy the updated LookML model to your production environment.
5. Customize and Share:
	- Open the "Focus" dashboard within Looker by navigating to the LookML Dashboards folder.
	- Make a copy of the dashboard.
	- Customize the copied dashboard to your specific needs and preferences.
	- Share the customized dashboard with your team members or other stakeholders.

## Important Notes
- Temporary Tables: Unlike BigQuery Views, Looker utilizes temporary tables. The provided LookML code will create and manage these tables automatically, so you won't need to create them manually.
- Data Validation: Always double-check your data in Looker to ensure it aligns with your expectations after making changes.

