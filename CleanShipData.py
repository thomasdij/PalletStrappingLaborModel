import os
import glob
import pandas as pd
from sqlalchemy import create_engine

# Define the PostgreSQL connection parameters
USER = 'postgres'
PASSWORD = 'password'
HOST = 'localhost'
PORT = 'port'
DATABASE = 'sunpower'

# Define the name of the table to populate
TABLE_NAME = 'shipping_report'
# Define the path of the folder containing files to insert into the database
DATA_FOLDER = r'path1'

# Create a connection string for the PostgreSQL server
conn_str = f'postgresql://{USER}:{PASSWORD}@{HOST}:{PORT}/{DATABASE}'

# Create a SQLAlchemy engine to connect to the PostgreSQL server
engine = create_engine(conn_str)

def insert_df_to_server(df):
    # Upload the DataFrame to the existing table in the PostgreSQL server
    df.to_sql(TABLE_NAME, engine, if_exists='append', index=False)

# Loop through all Excel files in the specified folder
for filename in glob.glob(os.path.join(DATA_FOLDER, '*.xlsx')):
    # Read the Excel file into a Pandas DataFrame
    # Report comes from SAP BI with coded column names i.e. KJCORF and a multi-column summary that are removed
    df = pd.read_excel(filename, skiprows=11)

    # Drop all empty columns
    df.dropna(axis='columns', how='all', inplace=True)
    
    # Drop the last row, this row contains a sum and this cannot be changed when the original excel file is generated
    df = df.drop(df.index[-1])

    # Numbers come formatted with commas which needs to be cleaned to convert to int for numerical operations
    df = df.replace(',', '', regex=True)

    # Easily understood column names are added in place of previous almost unintelligible ones
    df = df.rename(columns={'Unnamed: 1': 'ship_date', 'Unnamed: 2': 'delivery_number', 'Unnamed: 3': 'order_number',\
                             'Unnamed: 4': 'item_number', 'Unnamed: 5': 'pick_type', 'Unnamed: 6': 'total_qty_requested',\
                                  'Unnamed: 7': 'weight_per_line', 'Unnamed: 8': 'qty_ea_on_plt', 'Unnamed: 9': 'qty_ea_in_cs',\
                                      'Unnamed: 10': 'line_cost', '2': 'qty_pv_plt_picks', '3': 'qty__bos_plt_picks',\
                                          '4': 'qty_rail_plt_picks', '5': 'qty_pv_cs_picks', '6': 'qty_bos_cs_picks',\
                                              '7': 'qty_rail_cs_picks', '8': 'qty_pv_ea_picks', '10': 'qty_bos_ea_picks',\
                                                  '11': 'qty_rail_ea_picks', 
    }) 
    df['item_number'] = df['item_number'].str.strip()

    # Call the function to insert the DataFrame into the server
    insert_df_to_server(df)
