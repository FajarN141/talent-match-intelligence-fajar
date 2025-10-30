import streamlit as st
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from sqlalchemy import create_engine

# Membuat koneksi ke PostgreSQL
engine = create_engine('postgresql://{yourusername}:{yourpassword}@localhost:{yourlocalport}/{yourdatabase}')

# Mengambil data dari PostgreSQL (Data Karyawan)
query = "SELECT * FROM final_table"
df = pd.read_sql(query, engine)

# Judul Aplikasi
st.title("Employee Talent Match Rate")

# Ranked Talent List
st.subheader("Ranked Talent List")
st.write(df[['employee_id','fullname','education_level','final_match_rate']])

# Pilih berapa banyak kandidat yang ingin ditampilkan
top_k = st.slider('Tampilkan berapa banyak kandidat teratas?', 1, 10, 5)
st.write(df[['employee_id','fullname','education_level','final_match_rate']].head(top_k))

# Input Parameter untuk pencarian
st.subheader("Filter Kriteria Kandidat")

# Input parameter karyawan yang diinginkan
strengths = st.multiselect("Pilih Strengths", ["Strategic", "Learner", "Achiever", "Relator", "Analytical"])

# Menampilkan definisi dari Strengths yang dipilih
if "Strategic" in strengths:
    st.markdown("### **Strategic**")
    st.write("Strategic berarti kemampuan untuk merencanakan dengan hati-hati dan berpikir jangka panjang. Individu yang memiliki kekuatan ini sering kali dapat melihat berbagai pilihan dan merencanakan langkah-langkah yang tepat untuk mencapai tujuan.")
if "Learner" in strengths:
    st.markdown("### **Learner**")
    st.write("Learner mengacu pada kemampuan untuk belajar dan mengembangkan keterampilan baru dengan cepat. Individu dengan kekuatan ini memiliki rasa ingin tahu yang tinggi dan selalu mencari cara untuk meningkatkan pengetahuan mereka.")
if "Achiever" in strengths:
    st.markdown("### **Achiever**")
    st.write("Achiever berarti dorongan untuk mencapai sesuatu yang signifikan. Individu dengan kekuatan ini cenderung menetapkan dan menyelesaikan tujuan dengan tekad dan ketekunan.")
if "Relator" in strengths:
    st.markdown("### **Relator**")
    st.write("Relator merujuk pada kemampuan untuk membangun hubungan yang kuat dan mendalam dengan orang lain. Individu dengan kekuatan ini mudah berhubungan dengan orang lain dan sering menjadi pusat hubungan tim.")
if "Analytical" in strengths:
    st.markdown("### **Analytical**")
    st.write("Analytical berarti kemampuan untuk berpikir logis dan memecahkan masalah. Individu yang memiliki kekuatan ini cenderung menganalisis informasi secara mendalam dan mencari pola untuk membuat keputusan yang lebih baik.")

# Input dan definisi IQ
st.markdown("### **Definisi IQ (Intelligence Quotient)**")
st.write("IQ atau **Intelligence Quotient** adalah ukuran yang digunakan untuk menilai kemampuan intelektual seseorang. Dalam konteks ini, IQ digunakan untuk menilai kemampuan kognitif dasar seorang karyawan dalam menyelesaikan tugas-tugas yang kompleks dan memecahkan masalah secara efektif.")
iq_min = st.slider("IQ minimum", min_value=50, max_value=160, value=100)

#Input dan Definisi GTQ
st.markdown("### **Definisi GTQ (General Technical Quotient)**")
st.write("GTQ atau **General Technical Quotient** adalah ukuran untuk menilai kecakapan teknis dan kemampuan seseorang dalam menangani masalah teknis dan operasional. GTQ memberikan gambaran tentang seberapa baik seseorang dapat beradaptasi dengan perkembangan teknologi dan memecahkan masalah terkait teknologi.")
gtq_min = st.slider("GTQ minimum", min_value=5, max_value=50, value=10)

# Filter berdasarkan Pilar Leadership
pillar = st.selectbox("Pilih Pillar Leadership", ["sea", "qdd", "vcu", "lie"])

# Menampilkan definisi Pilar Leadership yang dipilih
if pillar == "sea":
    st.markdown("### Pilar Leadership: **SEA** (Strategic, Entrepreneurial, and Ambitious)")
    st.write("Pilar SEA berfokus pada kemampuan strategis, berpikir jangka panjang, dan memiliki jiwa kewirausahaan serta ambisi untuk mencapai tujuan yang lebih besar.")
elif pillar == "qdd":
    st.markdown("### Pilar Leadership: **QDD** (Quality, Dedication, and Drive)")
    st.write("Pilar QDD menekankan pentingnya kualitas dalam pekerjaan, dedikasi untuk mencapai hasil terbaik, dan dorongan untuk terus berusaha keras.")
elif pillar == "vcu":
    st.markdown("### Pilar Leadership: **VCU** (Vision, Courage, and Understanding)")
    st.write("Pilar VCU berkaitan dengan visi jauh ke depan, keberanian untuk mengambil risiko yang tepat, dan pemahaman mendalam terhadap situasi serta orang lain.")
else:
    st.markdown("### Pilar Leadership: **LIE** (Leadership, Integrity, and Empathy)")
    st.write("Pilar LIE menekankan pada kepemimpinan yang inspiratif, integritas tinggi, dan kemampuan untuk merasakan dan memahami kebutuhan orang lain dengan empati.")

# Input lainnya
education_level = st.selectbox("Pilih Jenjang Pendidikan", df['education_level'].unique())
experience_min = st.slider("Tahun Pengalaman Kerja Minimum", min_value=0, max_value=30, value=2)
mbti = st.selectbox("Pilih MBTI yang cocok", ["INTJ", "ENTP", "INFP", "ESTJ", "ISFJ", "ENFP", "ISTP", "ISFP"])

# Button untuk mencari kandidat yang sesuai
if st.button("Cari Kandidat"):
    # Filter DataFrame berdasarkan input pengguna
    filtered_df = df[
        (df['s_strategic'].isin(strengths)) &
        (df['iq'] >= iq_min) & 
        (df['gtq'] >= gtq_min) &
        (df['pillar_sea'] == pillar) & 
        (df['education_level'] == education_level) & 
        (df['years_of_service'] >= experience_min) & 
        (df['mbti'] == mbti)
    ]
    
    # Hitung Match Rate berdasarkan input pengguna
    filtered_df['match_rate'] = (
        0.30 * filtered_df['iq'] + 
        0.25 * filtered_df['gtq'] + 
        0.20 * filtered_df['pillar_sea'] + 
        0.15 * filtered_df['years_of_service'] + 
        0.10 * filtered_df['s_strategic']
    )
    
    # Menampilkan hasil pencarian dalam bentuk tabel
    st.subheader("Kandidat yang Sesuai")
    st.write(filtered_df[['employee_id', 'fullname', 'match_rate']])

    # Visualisasi Match Rate dengan bar chart
    st.subheader('Visualisasi Match Rate')
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.barplot(x='employee_id', y='match_rate', data=filtered_df, ax=ax)
    ax.set_title('Match Rate untuk Kandidat Terpilih')
    st.pyplot(fig)

    # Visualisasi Z-Score untuk berbagai atribut
    st.subheader('Z-Score Visualization')

    # Visualisasi Z-Score untuk IQ
    fig, ax = plt.subplots(figsize=(10, 6))  # Membuat objek fig dan ax
    sns.histplot(filtered_df['iq'], kde=True, ax=ax)
    ax.set_title('Z-Score Distribution for IQ')  # Menambahkan judul pada ax
    st.pyplot(fig)  # Menampilkan figure dengan st.pyplot()

# Menampilkan informasi tambahan jika tidak ada data yang ditemukan
else:
    st.write("Silakan pilih parameter pencarian untuk mencari kandidat.")

